public with sharing class OrderService implements IOrderService {

    private static final String AUTH_URL = 'https://login.salesforce.com/services/oauth2/token';
    private static final String EXTERNAL_INSTANCE_URL = 'https://pwcsandbox53-dev-ed.develop.my.salesforce.com'; 
    private static final String API_VERSION = 'v63.0'; 
    private static final String ORDER_ENDPOINT = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/Order/';
    private static final String ORDER_ITEM_QUERY_ENDPOINT = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/query?q=SELECT+Id,OrderId,Product2Id,Quantity,UnitPrice+FROM+OrderItem+WHERE+OrderId='; // Example Query
    private static final String PRODUCT_ENDPOINT = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/Product2/';
    private static final String ACCOUNT_ENDPOINT = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/Account/';

    public void getOrdersByEmailFromExternal(String email) {
        if (String.isBlank(email)) {
            System.debug('Email parameter is blank. Aborting getOrdersByEmailFromExternal.');
            return;
        }
        String accessToken = authenticate();
        if (accessToken == null) {
            System.debug('Authentication failed. Aborting getOrdersByEmailFromExternal.');
            return;
        }
        String soql = 'SELECT Id, AccountId FROM Order WHERE Account.PersonEmail = \'' 
            + String.escapeSingleQuotes(email) + '\'';
        String encodedQuery = EncodingUtil.urlEncode(soql, 'UTF-8');
        String queryEndpoint = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/query?q=' + encodedQuery;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(queryEndpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Content-Type', 'application/json');

        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (System.CalloutException ce) {
            System.debug('Callout failed in getOrdersByEmailFromExternal: ' + ce.getMessage());
            return;
        }

        if (res.getStatusCode() == 200) {
            Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> records = (List<Object>) jsonResponse.get('records');
            if (records == null || records.isEmpty()) {
                System.debug('No orders found in external org for email: ' + email);
                return;
            }
            List<ExternalOrderData> allExternalOrderData = new List<ExternalOrderData>();
            for (Object rec : records) {
                Map<String, Object> orderRecord = (Map<String, Object>) rec;
                String externalOrderId = (String) orderRecord.get('Id');
                String externalAccountId = (String) orderRecord.get('AccountId');
                if (externalOrderId != null && externalAccountId != null) {
                    ExternalOrderData eod = fetchExternalOrderData(externalOrderId, externalAccountId, accessToken);
                    if (eod != null) {
                        allExternalOrderData.add(eod);
                    } else {
                        System.debug('Skipping order due to failed external data fetch for order ID: ' + externalOrderId);
                    }
                } else {
                    System.debug('Skipping order with missing externalOrderId or externalAccountId.');
                }
            }
            for (ExternalOrderData eod : allExternalOrderData) {
                syncOrderDataWithExternalData(eod);
            }
        } else {
            System.debug('Failed to query external orders. Status: ' + res.getStatusCode() + ' Body: ' + res.getBody());
        }
    }

    private class ExternalOrderData {
        public String externalOrderId;
        public String externalAccountId;
        public ExternalOrderDTO externalOrderDTO;
        public List<ExternalOrderItemDTO> externalOrderItemDTOs;
        public Map<String, ExternalProductDTO> externalProductDTOMap;
    }

    private ExternalOrderData fetchExternalOrderData(String externalOrderId, String externalAccountId, String accessToken) {
        ExternalOrderData eod = new ExternalOrderData();
        eod.externalOrderId = externalOrderId;
        eod.externalAccountId = externalAccountId;

        String orderJson = getExternalRecordJsonById(ORDER_ENDPOINT, externalOrderId, accessToken);
        if (String.isBlank(orderJson)) {
            System.debug('Failed to fetch external order details for ID: ' + externalOrderId);
            return null;
        }
        eod.externalOrderDTO = (ExternalOrderDTO) JSON.deserialize(orderJson, ExternalOrderDTO.class);

        String orderItemsJson = getExternalOrderItemsJson(externalOrderId, accessToken);
        if (String.isBlank(orderItemsJson)) {
            System.debug('No order items found or failed to fetch items for external order ID: ' + externalOrderId);
            return null;
        }
        eod.externalOrderItemDTOs = (List<ExternalOrderItemDTO>) JSON.deserialize(orderItemsJson, List<ExternalOrderItemDTO>.class);

        Set<String> externalProductIds = new Set<String>();
        for (ExternalOrderItemDTO item : eod.externalOrderItemDTOs) {
            if (String.isNotBlank(item.Product2Id)) {
                externalProductIds.add(item.Product2Id);
            }
        }

        eod.externalProductDTOMap = new Map<String, ExternalProductDTO>();
        for (String prodId : externalProductIds) {
            String productJson = getExternalRecordJsonById(PRODUCT_ENDPOINT, prodId, accessToken);
            if (String.isNotBlank(productJson)) {
                ExternalProductDTO productDTO = (ExternalProductDTO) JSON.deserialize(productJson, ExternalProductDTO.class);
                eod.externalProductDTOMap.put(prodId, productDTO);
            } else {
                System.debug('Warning: Failed to fetch details for external product ID: ' + prodId);
            }
        }
        return eod;
    }

    private void syncOrderDataWithExternalData(ExternalOrderData eod) {
        if (eod == null) {
            System.debug('syncOrderDataWithExternalData called with null data.');
            return;
        }
        try {
            Account localAccount = ensureLocalAccount(eod.externalAccountId, null);
            if (localAccount == null || localAccount.Id == null) {
                System.debug('Failed to find or create local Account for external ID: ' + eod.externalAccountId + '. Aborting order sync.');
                return;
            }

            Contract localContract = ensureDummyContract(localAccount.Id, eod.externalOrderId);
            if (localContract == null || localContract.Id == null) {
                System.debug('Failed to create dummy Contract for Account: ' + localAccount.Id + '. Aborting order sync.');
                return;
            }

            Map<String, Id> localProductIdMap = upsertProductsAndGetIds(eod.externalProductDTOMap);
            Map<String, Id> localPricebookEntryIdMap = ensurePricebookEntries(localProductIdMap);

            upsertOrderAndItems(
                eod.externalOrderDTO,
                eod.externalOrderItemDTOs,
                localAccount.Id,
                localContract.Id,
                localProductIdMap,
                localPricebookEntryIdMap
            );

            System.debug('Successfully synced data for external order ID: ' + eod.externalOrderId);

        } catch (Exception e) {
            System.debug('Error during syncOrderDataWithExternalData for external Order ID ' + eod.externalOrderId + ': ' + e.getMessage() + '\nStackTrace: ' + e.getStackTraceString());
        }
    }

    public void syncOrderData(String externalOrderId, String externalAccountId) {
        syncOrderData(externalOrderId, externalAccountId, null);
    }

    public void syncOrderData(String externalOrderId, String externalAccountId, String accessToken) {
        if (String.isBlank(externalOrderId) || String.isBlank(externalAccountId)) {
            System.debug('External Order ID and External Account ID are required.');
            return; 
        }

        try {
            if (accessToken == null) {
                accessToken = authenticate();
            }
            if (accessToken == null) {
                System.debug('Authentication failed. Aborting sync for Order: ' + externalOrderId);
                return;
            }

            ExternalOrderData eod = fetchExternalOrderData(externalOrderId, externalAccountId, accessToken);
            if (eod == null) {
                System.debug('Failed to fetch external order data for ID: ' + externalOrderId);
                return;
            }

            syncOrderDataWithExternalData(eod);

            System.debug('Successfully synced data for external order ID: ' + externalOrderId);

        } catch (Exception e) {
            System.debug('Error during syncOrderData for external Order ID ' + externalOrderId + ': ' + e.getMessage() + '\nStackTrace: ' + e.getStackTraceString());
        }
    }

    public String authenticate() {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(AUTH_URL);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

        try {
             req.setBody(
                'grant_type=password' +
                '&client_id=' + EncodingUtil.urlEncode(System.Label.OAuth_Client_ID, 'UTF-8') +
                '&client_secret=' + EncodingUtil.urlEncode(System.Label.OAuth_Client_Secret, 'UTF-8') +
                '&username=' + EncodingUtil.urlEncode(System.Label.OAuth_Username, 'UTF-8') +
                '&password=' + EncodingUtil.urlEncode(System.Label.OAuth_Password, 'UTF-8')
            );
        } catch (Exception e) {
             System.debug('OAuth Custom Label Error: ' + e.getMessage() + '. Please ensure OAuth labels are configured.');
             return null;
        }
        Http http = new Http();
        HttpResponse res = null;
        try {
            res = http.send(req);
        } catch (System.CalloutException ce) {
            System.debug('Authentication callout failed: ' + ce.getMessage());
            return null;
        }
        if (res != null && res.getStatusCode() == 200) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) result.get('access_token');
        } else {
            System.debug('OAuth authentication failed. Status: ' + (res != null ? String.valueOf(res.getStatusCode()) : 'No Response') + ' Body: ' + (res != null ? res.getBody() : 'N/A'));
            return null;
        }
    }

    private String getExternalRecordJsonById(String endpointBase, String recordId, String accessToken) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpointBase + recordId);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Content-Type', 'application/json');
        Http http = new Http();
        HttpResponse res = null;
        try {
             res = http.send(req);
        } catch (System.CalloutException ce) {
             System.debug('Get Record Details callout failed for endpoint ' + endpointBase + ' Id ' + recordId + ': ' + ce.getMessage());
             return null;
        }
        if (res != null && res.getStatusCode() == 200) {
            return res.getBody();
        } else {
            System.debug('External record detail fetch failed for endpoint ' + endpointBase + ' Id ' + recordId + '. Status: ' + (res != null ? String.valueOf(res.getStatusCode()) : 'No Response') + ' Body: ' + (res != null ? res.getBody() : 'N/A'));
            return null;
        }
    }

    private String getExternalOrderItemsJson(String externalOrderId, String accessToken) {
        String query = 'SELECT Id, OrderId, Product2Id, Quantity, UnitPrice FROM OrderItem WHERE OrderId = \'' + externalOrderId + '\'';
        String encodedQuery = EncodingUtil.urlEncode(query, 'UTF-8');
        String queryEndpoint = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/query?q=' + encodedQuery;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(queryEndpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Content-Type', 'application/json');

        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (System.CalloutException ce) {
            System.debug('Callout failed in getExternalOrderItemsJson: ' + ce.getMessage());
            return null;
        }

        if (res.getStatusCode() == 200) {
            Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> records = (List<Object>) jsonResponse.get('records');
            if (records == null || records.isEmpty()) {
                System.debug('No order items found in external org for order ID: ' + externalOrderId);
                return null;
            }
            return JSON.serialize(records);
        } else {
            System.debug('Failed to query external order items. Status: ' + res.getStatusCode() + ' Body: ' + res.getBody());
            return null;
        }
    }

    private Account ensureLocalAccount(String externalAccountId, String accessToken) {
        List<Account> existingAccounts = AccountSelector.selectByExternalId(externalAccountId);
        if (!existingAccounts.isEmpty()) {
            System.debug('Found existing local Account: ' + existingAccounts[0].Id);
            return existingAccounts[0];
        } else {
            System.debug('Local Account not found for external ID: ' + externalAccountId + '. Fetching from external org.');
            Map<String, Object> externalAccountData = (Map<String, Object>) JSON.deserializeUntyped(getExternalRecordJsonById(ACCOUNT_ENDPOINT, externalAccountId, accessToken));
            if (externalAccountData != null) {
                return upsertLocalAccount(externalAccountData);
            } else {
                System.debug('Failed to fetch external account data for ID: ' + externalAccountId);
                return null;
            }
        }
    }

    private Account upsertLocalAccount(Map<String, Object> data) {
        String externalId = (String) data.get('Id');
        if (String.isBlank(externalId)) return null;

        Schema.SObjectField externalIdField = Account.SObjectType.getDescribe().fields.getMap().get('External_Id__c');
        if(externalIdField == null){
            System.debug('Error: External_Id__c field missing on Account.');
            return null; 
        }

        List<Account> existing = [SELECT Id FROM Account WHERE External_Id__c = :externalId LIMIT 1];
        Account acc = !existing.isEmpty() ? new Account(Id = existing[0].Id) : new Account();

        acc.Name = (String) data.get('Name');
        acc.FirstName = (String) data.get('FirstName');
        acc.LastName = (String) data.get('LastName');
        acc.PersonEmail = (String) data.get('PersonEmail');
        acc.Phone = (String) data.get('Phone');
        acc.External_Id__c = externalId;

        try {
            Database.UpsertResult result = Database.upsert(acc, externalIdField, false);
            if (result.isSuccess()) {
                System.debug((result.isCreated() ? 'Inserted' : 'Updated') + ' Account: ' + result.getId());
                return [SELECT Id, Name, PersonContactId, External_Id__c FROM Account WHERE Id = :result.getId()];
            } else {
                System.debug('Account upsert failed for external ID ' + externalId + ': ' + result.getErrors()[0].getMessage());
                return null;
            }
        } catch (Exception e) {
            System.debug('Exception during Account upsert for external ID ' + externalId + ': ' + e.getMessage());
            return null;
        }
    }

    private Contract ensureDummyContract(Id localAccountId, String externalOrderId) {
        List<Contract> existingContracts = [
            SELECT Id FROM Contract
            WHERE AccountId = :localAccountId
            AND Status = 'Draft'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!existingContracts.isEmpty()) {
            System.debug('Found existing dummy Contract: ' + existingContracts[0].Id);
            return existingContracts[0];
        } else {
            System.debug('Creating new dummy Contract for Account: ' + localAccountId);
            Contract newContract = new Contract(
                AccountId = localAccountId,
                StartDate = Date.today(),
                Status = 'Draft',
                ContractTerm = 12
            );
            try {
                insert newContract;
                System.debug('Inserted new dummy Contract: ' + newContract.Id);
                return newContract;
            } catch (Exception e) {
                System.debug('Failed to insert dummy Contract: ' + e.getMessage());
                return null;
            }
        }
    }

    private Map<String, Id> upsertProductsAndGetIds(Map<String, ExternalProductDTO> externalProductDTOMap) {
        Map<String, Id> localProductIds = new Map<String, Id>();

        Schema.SObjectField externalIdField = Product2.SObjectType.getDescribe().fields.getMap().get('External_Id__c');
        if(externalIdField == null){
            System.debug('Error: External_Id__c field missing on Product2.');
            return localProductIds;
        }

        Set<String> externalIds = externalProductDTOMap.keySet();
        Map<String, Product2> existingProductMap = new Map<String, Product2>();
        for(Product2 p : [SELECT Id, External_Id__c FROM Product2 WHERE External_Id__c IN :externalIds]) {
            existingProductMap.put(p.External_Id__c, p);
            localProductIds.put(p.External_Id__c, p.Id);
        }

        List<Product2> productsToInsert = new List<Product2>();
        List<Product2> productsToUpdate = new List<Product2>();

        for (String extId : externalProductDTOMap.keySet()) {
            ExternalProductDTO dto = externalProductDTOMap.get(extId);
            Product2 prod;
            if(existingProductMap.containsKey(extId)) {
                prod = existingProductMap.get(extId);
                prod.Name = dto.Name;
                prod.ProductCode = dto.ProductCode;
                prod.Description = dto.Description;
                prod.IsActive = true;
                productsToUpdate.add(prod);
            } else {
                prod = new Product2();
                prod.External_Id__c = extId;
                prod.Name = dto.Name;
                prod.ProductCode = dto.ProductCode;
                prod.Description = dto.Description;
                prod.IsActive = true;
                productsToInsert.add(prod);
            }
        }

        if (!productsToInsert.isEmpty()) {
            Database.SaveResult[] insertResults = Database.insert(productsToInsert, false);
            for (Integer i = 0; i < insertResults.size(); i++) {
                if (insertResults[i].isSuccess()) {
                    localProductIds.put(productsToInsert[i].External_Id__c, insertResults[i].getId());
                    System.debug('Inserted Product2: ' + insertResults[i].getId() + ' for External ID: ' + productsToInsert[i].External_Id__c);
                } else {
                    System.debug('Product2 insert failed for external ID ' + productsToInsert[i].External_Id__c + ': ' + insertResults[i].getErrors()[0].getMessage());
                }
            }
        }

        if (!productsToUpdate.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(productsToUpdate, false);
            for (Integer i = 0; i < updateResults.size(); i++) {
                if (updateResults[i].isSuccess()) {
                    localProductIds.put(productsToUpdate[i].External_Id__c, updateResults[i].getId());
                    System.debug('Updated Product2: ' + updateResults[i].getId() + ' for External ID: ' + productsToUpdate[i].External_Id__c);
                } else {
                    System.debug('Product2 update failed for external ID ' + productsToUpdate[i].External_Id__c + ': ' + updateResults[i].getErrors()[0].getMessage());
                }
            }
        }

        return localProductIds;
    }

    private Map<String, Id> ensurePricebookEntries(Map<String, Id> localProductIdMap) {
        Map<String, Id> pbeIdMap = new Map<String, Id>();
        if (localProductIdMap == null || localProductIdMap.isEmpty()) {
            return pbeIdMap;
        }

        Id standardPricebookId = Test.isRunningTest() ? Test.getStandardPricebookId() : [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
        if (standardPricebookId == null) {
            System.debug('Standard Pricebook ID not found. Cannot create PricebookEntries.');
            return pbeIdMap;
        }

        Set<Id> productIds = new Set<Id>(localProductIdMap.values());
        Map<Id, Id> productIdToPbeIdMap = new Map<Id, Id>();

        for (PricebookEntry pbe : [SELECT Id, Product2Id FROM PricebookEntry WHERE Pricebook2Id = :standardPricebookId AND Product2Id IN :productIds]) {
            productIdToPbeIdMap.put(pbe.Product2Id, pbe.Id);
        }

        List<PricebookEntry> pbesToInsert = new List<PricebookEntry>();
        for (String externalProdId : localProductIdMap.keySet()) {
            Id localProdId = localProductIdMap.get(externalProdId);
            if (productIdToPbeIdMap.containsKey(localProdId)) {
                pbeIdMap.put(externalProdId, productIdToPbeIdMap.get(localProdId));
            } else {
                PricebookEntry newPbe = new PricebookEntry(
                    Pricebook2Id = standardPricebookId,
                    Product2Id = localProdId,
                    UnitPrice = 1.00,
                    IsActive = true
                );
                pbesToInsert.add(newPbe);
            }
        }

        if (!pbesToInsert.isEmpty()) {
            try {
                Database.SaveResult[] insertResults = Database.insert(pbesToInsert, false);
                for(Integer i = 0; i < insertResults.size(); i++) {
                    Database.SaveResult sr = insertResults[i];
                    PricebookEntry insertedPbe = pbesToInsert[i];
                    String externalProdId = null;
                    for(String extId : localProductIdMap.keySet()){
                        if(localProductIdMap.get(extId) == insertedPbe.Product2Id){
                            externalProdId = extId;
                            break;
                        }
                    }

                    if(sr.isSuccess() && externalProdId != null) {
                        pbeIdMap.put(externalProdId, sr.getId());
                        System.debug('Inserted PricebookEntry: ' + sr.getId() + ' for Product: ' + insertedPbe.Product2Id);
                    } else {
                        System.debug('Failed to insert PricebookEntry for Product ' + insertedPbe.Product2Id + ': ' + (sr.isSuccess() ? 'Could not map back to External ID' : sr.getErrors()[0].getMessage()));
                    }
                }
            } catch (Exception e) {
                System.debug('Exception inserting PricebookEntries: ' + e.getMessage());
            }
        }

        return pbeIdMap;
    }

    private void upsertOrderAndItems(
        ExternalOrderDTO externalOrderDTO,
        List<ExternalOrderItemDTO> externalOrderItemDTOs,
        Id localAccountId,
        Id localContractId,
        Map<String, Id> localProductIdMap,
        Map<String, Id> localPricebookEntryIdMap
    ) {
        if (externalOrderDTO == null) {
            System.debug('ExternalOrderDTO is null. Cannot upsert.');
            return;
        }
        String externalOrderId = externalOrderDTO.Id;
        if (String.isBlank(externalOrderId)) {
            System.debug('External Order ID missing from DTO. Cannot upsert.');
            return;
        }

        List<Order> ordersToInsert = new List<Order>();
        List<Order> ordersToUpdate = new List<Order>();
        List<OrderItem> itemsToInsert = new List<OrderItem>();
        List<OrderItem> itemsToUpdate = new List<OrderItem>();

        List<Order> existingOrders = [SELECT Id, External_Id__c FROM Order WHERE External_Id__c = :externalOrderId LIMIT 1];
        Order orderToProcess;
        if (!existingOrders.isEmpty()) {
            orderToProcess = existingOrders[0];
            orderToProcess.AccountId = localAccountId;
            orderToProcess.ContractId = localContractId;
            orderToProcess.Pricebook2Id = Test.isRunningTest() ? Test.getStandardPricebookId() : [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
            orderToProcess.Status = externalOrderDTO.Status;
            orderToProcess.EffectiveDate = Date.valueOf(externalOrderDTO.EffectiveDate.substring(0,10));
            ordersToUpdate.add(orderToProcess);
        } else {
            orderToProcess = new Order();
            orderToProcess.External_Id__c = externalOrderId;
            orderToProcess.AccountId = localAccountId;
            orderToProcess.ContractId = localContractId;
            orderToProcess.Pricebook2Id = Test.isRunningTest() ? Test.getStandardPricebookId() : [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
            orderToProcess.Status = externalOrderDTO.Status;
            orderToProcess.EffectiveDate = Date.valueOf(externalOrderDTO.EffectiveDate.substring(0,10));
            ordersToInsert.add(orderToProcess);
        }

        Id localOrderId = null;
        if (!ordersToInsert.isEmpty()) {
            Database.SaveResult[] insertResults = Database.insert(ordersToInsert, false);
            if (insertResults[0].isSuccess()) {
                localOrderId = insertResults[0].getId();
                System.debug('Inserted Order: ' + localOrderId);
            } else {
                System.debug('Order insert failed for external ID ' + externalOrderId + ': ' + insertResults[0].getErrors()[0].getMessage());
                return;
            }
        } else if (!ordersToUpdate.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(ordersToUpdate, false);
            if (updateResults[0].isSuccess()) {
                localOrderId = updateResults[0].getId();
                System.debug('Updated Order: ' + localOrderId);
            } else {
                System.debug('Order update failed for external ID ' + externalOrderId + ': ' + updateResults[0].getErrors()[0].getMessage());
                return;
            }
        }

        if (localOrderId == null) {
            System.debug('Failed to get local Order Id after insert/update.');
            return;
        }

        Set<String> externalItemIds = new Set<String>();
        for(ExternalOrderItemDTO itemDTO : externalOrderItemDTOs) {
             externalItemIds.add(itemDTO.Id);
        }

        Map<String, OrderItem> existingItemMap = new Map<String, OrderItem>();
        if(!externalItemIds.isEmpty()){
            for(OrderItem oi : [SELECT Id, External_Id__c FROM OrderItem WHERE External_Id__c IN :externalItemIds]) {
                existingItemMap.put(oi.External_Id__c, oi);
            }
        }

        for (ExternalOrderItemDTO itemDTO : externalOrderItemDTOs) {
            String externalItemId = itemDTO.Id;
            String externalProductId = itemDTO.Product2Id;

            if (String.isBlank(externalItemId) || String.isBlank(externalProductId) || !localPricebookEntryIdMap.containsKey(externalProductId)) {
                System.debug('Skipping OrderItem upsert due to missing External Item ID, External Product ID, or local PricebookEntry. External Item ID: ' + externalItemId);
                continue;
            }

            Id localPbeId = localPricebookEntryIdMap.get(externalProductId);
            OrderItem item;
            if(existingItemMap.containsKey(externalItemId)) {
                item = existingItemMap.get(externalItemId);
                item.OrderId = localOrderId;
                item.PricebookEntryId = localPbeId;
                item.Quantity = itemDTO.Quantity != null ? itemDTO.Quantity : 0;
                item.UnitPrice = itemDTO.UnitPrice != null ? itemDTO.UnitPrice : 0;
                itemsToUpdate.add(item);
            } else {
                item = new OrderItem();
                item.External_Id__c = externalItemId;
                item.OrderId = localOrderId;
                item.PricebookEntryId = localPbeId;
                item.Quantity = itemDTO.Quantity != null ? itemDTO.Quantity : 0;
                item.UnitPrice = itemDTO.UnitPrice != null ? itemDTO.UnitPrice : 0;
                itemsToInsert.add(item);
            }
        }

        if (!itemsToInsert.isEmpty()) {
            Database.SaveResult[] insertResults = Database.insert(itemsToInsert, false);
            for (Integer i = 0; i < insertResults.size(); i++) {
                if (insertResults[i].isSuccess()) {
                    System.debug('Inserted OrderItem: ' + insertResults[i].getId() + ' for External ID: ' + itemsToInsert[i].External_Id__c);
                } else {
                    System.debug('OrderItem insert failed for external ID ' + itemsToInsert[i].External_Id__c + ': ' + insertResults[i].getErrors()[0].getMessage());
                }
            }
        }

        if (!itemsToUpdate.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(itemsToUpdate, false);
            for (Integer i = 0; i < updateResults.size(); i++) {
                if (updateResults[i].isSuccess()) {
                    System.debug('Updated OrderItem: ' + updateResults[i].getId() + ' for External ID: ' + itemsToUpdate[i].External_Id__c);
                } else {
                    System.debug('OrderItem update failed for external ID ' + itemsToUpdate[i].External_Id__c + ': ' + updateResults[i].getErrors()[0].getMessage());
                }
            }
        }
    }
}