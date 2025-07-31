public with sharing class omri {

    public static final String AUTH_URL ='https://login.salesforce.com/services/oauth2/token';
    public static final String EXTERNAL_INSTANCE_URL = 'https://pwcsandbox53-dev-ed.develop.my.salesforce.com';
    public static final String API_VERSION = 'v63.0';
    public static final String ACCOUNT_ENDPOINT = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/Account/';
    public static final String CONTACT_ENDPOINT = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/Contact/';
    // Corrected API version usage here to be consistent with API_VERSION constant
    public static final String PRODUCT_ENDPOINT = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/Product2/';
    public static final String ORDER_ENDPOINT = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/order/';

    public enum RefundStatus {
        NoRefund,
        Refund,
        HalfRefund,
        Exchange
    }

    // Wrapper class for Order data to send to LWC
    public class OrderData {
        @AuraEnabled public String orderId;
        @AuraEnabled public String accountId;
        @AuraEnabled public Map<String, Object> orderDetails;
        @AuraEnabled public Map<String, Object> accountDetails;
        @AuraEnabled public Map<String, Object> contactDetails;
        @AuraEnabled public List<OrderItemDetail> orderItems;
    }

    // Wrapper class for Order Item data to send to LWC
    public class OrderItemDetail {
        @AuraEnabled public String orderItemId;
        @AuraEnabled public String productId;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Map<String, Object> productDetails;
    }

    // DTO classes for updateExternalOrderItems
    public class AttributesDTO {
        @AuraEnabled public String type;
        public AttributesDTO(String type) {
            this.type = type;
        }
    }

    public class OrderItemUpdateDTO {
        @AuraEnabled public AttributesDTO attributes;
        @AuraEnabled public String Id;
        @AuraEnabled public Decimal Quantity;
        @AuraEnabled public Decimal UnitPrice;
    }

    public class OrderItemUpdateResultDTO {
        @AuraEnabled public String id;
        @AuraEnabled public Boolean success;
        @AuraEnabled public List<Object> errors;
    }

    public class CompositeRequestDTO {
        @AuraEnabled public Boolean allOrNone;
        @AuraEnabled public List<OrderItemUpdateDTO> records;
        public CompositeRequestDTO(Boolean allOrNone, List<OrderItemUpdateDTO> records) {
            this.allOrNone = allOrNone;
            this.records = records;
        }
    }
    @AuraEnabled(cacheable=true)
public static Account getAccountById(Id recordId) {
    return [SELECT Id, Name, PersonEmail FROM Account WHERE Id = :recordId LIMIT 1];
}


    /**
     * Updates the refund status of an external order.
     * @param externalOrderId The ID of the external order.
     * @param refundStatus The desired refund status (e.g., 'Refund', 'NoRefund').
     * @return True if the update was successful, false otherwise.
     */
    @AuraEnabled(cacheable=false) // Set to false because this method performs a DML operation (PATCH)
    public static Boolean refundStatus(String externalOrderId, String refundStatus) {
        if (String.isBlank(externalOrderId)) {
            System.debug('refundStatus: externalOrderId is blank.');
            return false;
        }
        if (String.isBlank(refundStatus)) {
            System.debug('refundStatus: refundStatus is blank.');
            return false;
        }

        String statusToSend = refundStatus; // Use the input refundStatus string directly, unless overridden by date logic.

        String accessToken = authenticate();
        if (accessToken == null) {
            System.debug('refundStatus: Authentication failed.');
            return false;
        }

        String orderJson = getExternalRecordJsonById(EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/Order/', externalOrderId, accessToken);
        if (String.isBlank(orderJson)) {
            System.debug('refundStatus: Failed to fetch order JSON for Id: ' + externalOrderId);
            return false;
        }

        Map<String, Object> orderData;
        try {
            orderData = (Map<String, Object>) JSON.deserializeUntyped(orderJson);
        } catch (Exception e) {
            System.debug('refundStatus: Failed to deserialize order JSON: ' + e.getMessage());
            return false;
        }

        if (!orderData.containsKey('EffectiveDate') || orderData.get('EffectiveDate') == null) {
            System.debug('refundStatus: Order JSON missing EffectiveDate.');
            return false;
        }

        String effectiveDateStr = (String) orderData.get('EffectiveDate');
        Date effectiveDate;
        try {
            effectiveDate = Date.valueOf(effectiveDateStr);
        } catch (Exception e) {
            System.debug('refundStatus: Failed to parse EffectiveDate: ' + effectiveDateStr);
            return false;
        }

        Date twoMonthsAgo = Date.today().addMonths(-2);
        if (effectiveDate <= twoMonthsAgo) {
            statusToSend = omri.RefundStatus.NoRefund.name(); // Override to "NoRefund"
        }

        // Prepare PATCH request to update Refund_Status__c field
        Map<String, Object> updateFields = new Map<String, Object>();
        updateFields.put('Refund_Status__c', statusToSend);

        String patchEndpoint = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/Order/' + externalOrderId;
        HttpRequest req = new HttpRequest();
        req.setEndpoint(patchEndpoint);
        req.setMethod('PATCH');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(updateFields));

        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (System.CalloutException ce) {
            System.debug('refundStatus: Callout failed: ' + ce.getMessage());
            return false;
        }

        if (res.getStatusCode() == 204) {
            System.debug('refundStatus: Successfully updated Refund_Status__c to ' + statusToSend + ' for order ' + externalOrderId);
            return true;
        } else {
            System.debug('refundStatus: Failed to update Refund_Status__c. Status: ' + res.getStatusCode() + ' Body: ' + res.getBody());
            return false;
        }
    }

    /**
     * Fetches orders from the external system by email and retrieves their detailed information,
     * including associated account, contact, order items, and product details.
     * @param email The email address to search for orders.
     * @return A list of OrderData wrapper objects containing comprehensive order details.
     */
    @AuraEnabled(cacheable=false) // Set to true because this method only reads data
    public static List<OrderData> getOrdersAndDetailsByEmail(String email) {
        List<OrderData> resultOrders = new List<OrderData>();

        if (String.isBlank(email)) {
            System.debug('Email parameter is blank. Aborting getOrdersAndDetailsByEmail.');
            return resultOrders;
        }
        String accessToken = authenticate();
        if (accessToken == null) {
            System.debug('Authentication failed. Aborting getOrdersAndDetailsByEmail.');
            return resultOrders;
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
            System.debug('Callout failed in getOrdersAndDetailsByEmail: ' + ce.getMessage());
            return resultOrders;
        }

        if (res.getStatusCode() == 200) {
            Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> records = (List<Object>) jsonResponse.get('records');
            if (records == null || records.isEmpty()) {
                System.debug('No orders found in external org for email: ' + email);
                return resultOrders;
            }
            for (Object rec : records) {
                Map<String, Object> orderRecord = (Map<String, Object>) rec;
                String externalOrderId = (String) orderRecord.get('Id');
                String externalAccountId = (String) orderRecord.get('AccountId');

                if (externalOrderId != null && externalAccountId != null) {
                    OrderData currentOrderData = new OrderData();
                    currentOrderData.orderId = externalOrderId;
                    currentOrderData.accountId = externalAccountId;

                    // Fetch and store order details
                    String orderJson = getExternalRecordJsonById(EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/Order/', externalOrderId, accessToken);
                    if (String.isNotBlank(orderJson)) {
                        try {
                            currentOrderData.orderDetails = (Map<String, Object>) JSON.deserializeUntyped(orderJson);
                        } catch (Exception e) {
                            System.debug('Failed to deserialize order JSON for ID ' + externalOrderId + ': ' + e.getMessage());
                        }
                    }

                    // Fetch and store account data
                    String accountJson = getExternalRecordJsonById(ACCOUNT_ENDPOINT, externalAccountId, accessToken);
                    if (String.isNotBlank(accountJson)) {
                        try {
                            currentOrderData.accountDetails = (Map<String, Object>) JSON.deserializeUntyped(accountJson);
                        } catch (Exception e) {
                            System.debug('Failed to deserialize account JSON for ID ' + externalAccountId + ': ' + e.getMessage());
                        }
                    }

                    // Fetch and store contact data related to account
                    String contactQuery = 'SELECT Id FROM Contact WHERE AccountId = \'' + String.escapeSingleQuotes(externalAccountId) + '\' LIMIT 1';
                    String encodedContactQuery = EncodingUtil.urlEncode(contactQuery, 'UTF-8');
                    String contactQueryEndpoint = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/query?q=' + encodedContactQuery;
                    HttpRequest contactReq = new HttpRequest();
                    contactReq.setEndpoint(contactQueryEndpoint);
                    contactReq.setMethod('GET');
                    contactReq.setHeader('Authorization', 'Bearer ' + accessToken);
                    contactReq.setHeader('Content-Type', 'application/json');
                    Http contactHttp = new Http();
                    try {
                        HttpResponse contactRes = contactHttp.send(contactReq);
                        if (contactRes.getStatusCode() == 200) {
                            Map<String, Object> contactResponse = (Map<String, Object>) JSON.deserializeUntyped(contactRes.getBody());
                            List<Object> contactRecords = (List<Object>) contactResponse.get('records');
                            if (contactRecords != null && !contactRecords.isEmpty()) {
                                Map<String, Object> contactRecord = (Map<String, Object>) contactRecords[0];
                                String contactId = (String) contactRecord.get('Id');
                                String contactJson = getExternalRecordJsonById(CONTACT_ENDPOINT, contactId, accessToken);
                                if (String.isNotBlank(contactJson)) {
                                    try {
                                        currentOrderData.contactDetails = (Map<String, Object>) JSON.deserializeUntyped(contactJson);
                                    } catch (Exception e) {
                                        System.debug('Failed to deserialize contact JSON for ID ' + contactId + ': ' + e.getMessage());
                                    }
                                }
                            } else {
                                System.debug('No contacts found for AccountId ' + externalAccountId);
                            }
                        } else {
                            System.debug('Failed to query contacts for AccountId ' + externalAccountId + '. Status: ' + contactRes.getStatusCode());
                        }
                    } catch (Exception e) {
                        System.debug('Exception while fetching contact data: ' + e.getMessage());
                    }

                    // Fetch and store order items and their product details
                    String orderItemsJson = getExternalOrderItemsJson(externalOrderId, accessToken);
                    if (String.isNotBlank(orderItemsJson)) {
                        try {
                            List<Object> orderItemsRaw = (List<Object>) JSON.deserializeUntyped(orderItemsJson);
                            List<OrderItemDetail> items = new List<OrderItemDetail>();
                            for (Object itemRaw : orderItemsRaw) {
                                Map<String, Object> itemMap = (Map<String, Object>) itemRaw;
                                OrderItemDetail itemDetail = new OrderItemDetail();
                                itemDetail.orderItemId = (String) itemMap.get('Id');
                                itemDetail.productId = (String) itemMap.get('Product2Id');
                                itemDetail.quantity = (Decimal) itemMap.get('Quantity');
                                itemDetail.unitPrice = (Decimal) itemMap.get('UnitPrice');

                                if (itemMap.containsKey('Product2Id') && itemMap.get('Product2Id') != null) {
                                    String productId = (String) itemMap.get('Product2Id');
                                    String productJson = getExternalRecordJsonById(PRODUCT_ENDPOINT, productId, accessToken);
                                    if (String.isNotBlank(productJson)) {
                                        try {
                                            itemDetail.productDetails = (Map<String, Object>) JSON.deserializeUntyped(productJson);
                                        } catch (Exception e) {
                                            System.debug('Failed to deserialize product JSON for ID ' + productId + ': ' + e.getMessage());
                                        }
                                    }
                                }
                                items.add(itemDetail);
                            }
                            currentOrderData.orderItems = items;
                        } catch (Exception e) {
                            System.debug('Failed to deserialize order items JSON: ' + e.getMessage());
                        }
                    }
                    resultOrders.add(currentOrderData);
                } else {
                    System.debug('Skipping order with missing externalOrderId or externalAccountId.');
                }
            }
        } else {
            System.debug('Failed to query external orders. Status: ' + res.getStatusCode() + ' Body: ' + res.getBody());
        }
        return resultOrders;
    }

    /**
     * Updates external order items using the Salesforce Composite API (PATCH).
     * @param localItemsToUpdate A list of OrderItem SObjects containing External_Id__c and fields to update.
     * @return A Map where keys are local OrderItem IDs and values are Booleans indicating success (true) or failure (false).
     */
    @AuraEnabled(cacheable=false) // Set to false because this method performs DML operations (PATCH)
    public static Map<Id, Boolean> updateExternalOrderItems(List<OrderItem> localItemsToUpdate) {
        System.debug('Starting updateExternalOrderItems with ' + (localItemsToUpdate != null ? localItemsToUpdate.size() : 0) + ' items.');
        Map<Id, Boolean> resultsMap = new Map<Id, Boolean>();
        if (localItemsToUpdate == null || localItemsToUpdate.isEmpty()) {
            System.debug('updateExternalOrderItems: No items provided to update.');
            return resultsMap;
        }
        String accessToken = authenticate();
        if (String.isBlank(accessToken)) {
            System.debug('updateExternalOrderItems: Authentication failed or access token is blank.');
            // Mark all as failed
            for(OrderItem item : localItemsToUpdate) {
                resultsMap.put(item.Id, false);
            }
            return resultsMap;
        }

        List<OrderItemUpdateDTO> recordsPayload = new List<OrderItemUpdateDTO>();
        Map<String, Id> externalToLocalIdMap = new Map<String, Id>(); // Helper to map results back

        for (OrderItem item : localItemsToUpdate) {
            if (String.isNotBlank(item.External_Id__c)) {
                OrderItemUpdateDTO dto = new OrderItemUpdateDTO();
                dto.attributes = new AttributesDTO('OrderItem');
                dto.Id = item.External_Id__c;
                dto.Quantity = item.Quantity;
                dto.UnitPrice = item.UnitPrice;
                recordsPayload.add(dto);
                externalToLocalIdMap.put(item.External_Id__c, item.Id);
                resultsMap.put(item.Id, false); // Default to false, update on success
            } else {
                System.debug('updateExternalOrderItems: Skipping item with blank External_Id__c: ' + item.Id);
                resultsMap.put(item.Id, false); // Mark as failed if External_Id__c is missing
            }
        }

        if (recordsPayload.isEmpty()) {
            System.debug('updateExternalOrderItems: No valid items found to update after filtering.');
            return resultsMap;
        }

        // Construct the request for the Collections API
        String endpoint = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/composite/sobjects';
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('PATCH'); // Use PATCH for updates
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Content-Type', 'application/json');

        // Set 'allOrNone' to false to allow partial success
        CompositeRequestDTO compositeRequest = new CompositeRequestDTO(false, recordsPayload);
        String requestBody = JSON.serialize(compositeRequest);
        System.debug('updateExternalOrderItems: Request body: ' + requestBody);
        req.setBody(requestBody);

        Http http = new Http();
        try {
            HttpResponse res = http.send(req);
            System.debug('updateExternalOrderItems: Response status: ' + res.getStatusCode());
            System.debug('updateExternalOrderItems: Response body: ' + res.getBody());
            // Status 200 indicates the request was processed (check individual results)
            if (res.getStatusCode() == 200) {
                // Using .class to deserialize into a List of the custom DTO
                List<OrderItemUpdateResultDTO> results = (List<OrderItemUpdateResultDTO>) JSON.deserialize(res.getBody(), List<OrderItemUpdateResultDTO>.class);
                for (OrderItemUpdateResultDTO itemResult : results) {
                    String externalId = itemResult.id;
                    Boolean success = itemResult.success;

                    if (externalToLocalIdMap.containsKey(externalId)) {
                        Id localId = externalToLocalIdMap.get(externalId);
                        resultsMap.put(localId, success); // Update the map with actual success status
                        if (!success) {
                            System.debug('Failed to update external OrderItem (External ID: ' + externalId + ', Local ID: ' + localId + '). Errors: ' + JSON.serialize(itemResult.errors));
                        } else {
                            System.debug('Successfully updated external OrderItem (External ID: ' + externalId + ', Local ID: ' + localId + ').');
                        }
                    }
                }
            } else {
                // Request itself failed (e.g., 400, 401, 500) - mark all attempted items as failed
                System.debug('Failed to update external OrderItems via Collections API. Status: ' + res.getStatusCode() + ' Body: ' + res.getBody());
                // The resultsMap already defaults to false for all items included in the payload
            }
        } catch (Exception e) {
            System.debug('Exception during updateExternalOrderItems callout: ' + e.getMessage());
            // The resultsMap already defaults to false for all items included in the payload
        }

        return resultsMap;
    }

    /**
     * Recreates an existing external order by fetching its details and items,
     * then inserting a new order and its corresponding items.
     * @param externalOrderId The ID of the original external order to reorder.
     * @return The ID of the newly created order, or null if reordering failed.
     */
    @AuraEnabled(cacheable=false) // Set to false because this method performs DML operations (POST)
    public static String reorderOrder(String externalOrderId) {
        if (String.isBlank(externalOrderId)) {
            System.debug('reorderOrder: externalOrderId is blank.');
            return null;
        }
        String accessToken = authenticate();
        if (accessToken == null) {
            System.debug('reorderOrder: Authentication failed.');
            return null;
        }

        // Fetch original order JSON
        String orderJson = getExternalRecordJsonById(EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/Order/', externalOrderId, accessToken);
        if (String.isBlank(orderJson)) {
            System.debug('reorderOrder: Failed to fetch order JSON for Id: ' + externalOrderId);
            return null;
        }

        // Fetch order items JSON
        String orderItemsJson = getExternalOrderItemsJson(externalOrderId, accessToken);
        if (String.isBlank(orderItemsJson)) {
            System.debug('reorderOrder: Failed to fetch order items JSON for order Id: ' + externalOrderId);
            return null;
        }

        Map<String, Object> originalOrderData;
        List<Object> originalOrderItems;
        try {
            originalOrderData = (Map<String, Object>) JSON.deserializeUntyped(orderJson);
            originalOrderItems = (List<Object>) JSON.deserializeUntyped(orderItemsJson);
        } catch (Exception e) {
            System.debug('reorderOrder: Failed to deserialize order or order items JSON: ' + e.getMessage());
            return null;
        }

        // Prepare new order data by copying relevant fields
        Map<String, Object> newOrderData = new Map<String, Object>();
        // Copy AccountId, Status, EffectiveDate, and other necessary fields
        if (originalOrderData.containsKey('AccountId')) {
            newOrderData.put('AccountId', originalOrderData.get('AccountId'));
        }
        if (originalOrderData.containsKey('Status')) {
            newOrderData.put('Status', originalOrderData.get('Status'));
        }
        if (originalOrderData.containsKey('EffectiveDate')) {
            newOrderData.put('EffectiveDate', String.valueOf(Date.today())); // Set new effective date to today
        }
        // Set Pricebook2Id to standard pricebook
        Id standardPricebookId = null;
        try {
            String queryUrl = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/query?q=' +
                EncodingUtil.urlEncode('SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1', 'UTF-8');
            System.debug('Query URL for standard Pricebook: ' + queryUrl);
            HttpRequest req = new HttpRequest();
            req.setEndpoint(queryUrl);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            req.setHeader('Content-Type', 'application/json');
            Http http = new Http();
            HttpResponse res;
            try {
                res = http.send(req);
            } catch (System.CalloutException ce) {
                System.debug('Failed to fetch standard Pricebook Id callout: ' + ce.getMessage());
                return null;
            }
            String pricebookJson = (res != null && res.getStatusCode() == 200) ?
            res.getBody() : null;
            System.debug('Pricebook query response: ' + pricebookJson);
            if (String.isNotBlank(pricebookJson)) {
                Map<String, Object> queryResult = (Map<String, Object>) JSON.deserializeUntyped(pricebookJson);
                if (queryResult != null && queryResult.containsKey('records')) {
                    List<Object> records = (List<Object>) queryResult.get('records');
                    if (records != null && !records.isEmpty()) {
                        Map<String, Object> firstRecord = (Map<String, Object>) records[0];
                        standardPricebookId = (String) firstRecord.get('Id');
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Failed to fetch standard Pricebook Id: ' + e.getMessage());
        }
        if (standardPricebookId != null) {
            newOrderData.put('Pricebook2Id', standardPricebookId);
        }
        // Add other fields as needed

        // Insert new order via REST API POST
        String createOrderEndpoint = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/Order/';
        HttpRequest createOrderReq = new HttpRequest();
        createOrderReq.setEndpoint(createOrderEndpoint);
        createOrderReq.setMethod('POST');
        createOrderReq.setHeader('Authorization', 'Bearer ' + accessToken);
        createOrderReq.setHeader('Content-Type', 'application/json');
        createOrderReq.setBody(JSON.serialize(newOrderData));

        Http http = new Http();
        HttpResponse createOrderRes;
        try {
            createOrderRes = http.send(createOrderReq);
        } catch (System.CalloutException ce) {
            System.debug('reorderOrder: Callout failed during order creation: ' + ce.getMessage());
            return null;
        }

        if (createOrderRes.getStatusCode() != 201) {
            System.debug('reorderOrder: Failed to create new order. Status: ' + createOrderRes.getStatusCode() + ' Body: ' + createOrderRes.getBody());
            return null;
        }

        Map<String, Object> createOrderResponse;
        try {
            createOrderResponse = (Map<String, Object>) JSON.deserializeUntyped(createOrderRes.getBody());
        } catch (Exception e) {
            System.debug('reorderOrder: Failed to deserialize create order response: ' + e.getMessage());
            return null;
        }

        String newOrderId = (String) createOrderResponse.get('id');
        if (String.isBlank(newOrderId)) {
            System.debug('reorderOrder: New order Id is blank.');
            return null;
        }

        // Insert order items linked to new order
        for (Object itemObj : originalOrderItems) {
            Map<String, Object> itemMap = (Map<String, Object>) itemObj;
            Map<String, Object> newItemData = new Map<String, Object>();
            newItemData.put('OrderId', newOrderId);
            if (itemMap.containsKey('Product2Id')) {
                String productId = (String) itemMap.get('Product2Id');
                newItemData.put('Product2Id', productId);
                // Get PricebookEntryId and ListPrice for productId
                Map<String, Object> pbeData = getPricebookEntryData(productId, accessToken);
                if (pbeData != null) {
                    if (pbeData.containsKey('Id')) {
                        newItemData.put('PricebookEntryId', pbeData.get('Id'));
                    }
                    if (pbeData.containsKey('UnitPrice')) {
                        newItemData.put('ListPrice', pbeData.get('UnitPrice'));
                    }
                }
            }
            if (itemMap.containsKey('Quantity')) {
                newItemData.put('Quantity', itemMap.get('Quantity'));
            }
            if (itemMap.containsKey('UnitPrice')) {
                newItemData.put('UnitPrice', itemMap.get('UnitPrice'));
            }
            // Add other fields as needed

            String createOrderItemEndpoint = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/OrderItem/';
            HttpRequest createOrderItemReq = new HttpRequest();
            createOrderItemReq.setEndpoint(createOrderItemEndpoint);
            createOrderItemReq.setMethod('POST');
            createOrderItemReq.setHeader('Authorization', 'Bearer ' + accessToken);
            createOrderItemReq.setHeader('Content-Type', 'application/json');
            createOrderItemReq.setBody(JSON.serialize(newItemData));
            try {
                HttpResponse createOrderItemRes = http.send(createOrderItemReq);
                if (createOrderItemRes.getStatusCode() != 201) {
                    System.debug('reorderOrder: Failed to create order item. Status: ' + createOrderItemRes.getStatusCode() + ' Body: ' + createOrderItemRes.getBody());
                    // Continue creating other items even if one fails
                }
            } catch (System.CalloutException ce) {
                System.debug('reorderOrder: Callout failed during order item creation: ' + ce.getMessage());
                // Continue creating other items even if one fails
            }
        }

        System.debug('reorderOrder: Successfully created new order with Id: ' + newOrderId);
        return newOrderId;
    }

    /**
     * Authenticates with the Salesforce OAuth endpoint using credentials from Custom Labels.
     * @return The access token string if authentication is successful, null otherwise.
     */
     @AuraEnabled(cacheable=true)
    public static String authenticate() {
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

    /**
     * Fetches a single external record's JSON by its ID from a specified endpoint.
     * @param endpointBase The base URL for the SObject endpoint (e.g., '.../sobjects/Account/').
     * @param recordId The ID of the record to fetch.
     * @param accessToken The OAuth access token.
     * @return The JSON string of the record, or null if not found or an error occurs.
     */
    @AuraEnabled(cacheable=true)
    public static String getExternalRecordJsonById(String endpointBase, String recordId, String accessToken) {
        if(String.isBlank(recordId) || String.isBlank(accessToken)){
            System.debug('Missing recordId or accessToken for getExternalRecordJsonById call.');
            return null;
        }
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

    /**
     * Fetches the JSON of order items associated with a given external order ID.
     * @param externalOrderId The ID of the external order.
     * @param accessToken The OAuth access token.
     * @return The JSON string of the order items records, or null if no items found or an error occurs.
     */
    public static String getExternalOrderItemsJson(String externalOrderId, String accessToken) {
        if(String.isBlank(externalOrderId) || String.isBlank(accessToken)){
            System.debug('Missing externalOrderId or accessToken for getExternalOrderItemsJson call.');
            return null;
        }
        String query = 'SELECT Id, OrderId, Product2Id, Quantity, UnitPrice FROM OrderItem WHERE OrderId = \'' + String.escapeSingleQuotes(externalOrderId) + '\'';
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

    /**
     * Retrieves PricebookEntry data (Id, UnitPrice) for a given product from the standard pricebook.
     * @param productId The ID of the product.
     * @param accessToken The OAuth access token.
     * @return A Map containing the PricebookEntry fields, or null if not found or an error occurs.
     */
    private static Map<String, Object> getPricebookEntryData(String productId, String accessToken) {
        if (String.isBlank(productId) || String.isBlank(accessToken)) {
            System.debug('getPricebookEntryData: productId or accessToken is blank.');
            return null;
        }
        // Query PricebookEntry for the product in the standard pricebook
        String soql = 'SELECT Id, UnitPrice FROM PricebookEntry WHERE Product2Id = \'' + String.escapeSingleQuotes(productId) + '\' AND Pricebook2.IsStandard = true LIMIT 1';
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
            System.debug('getPricebookEntryData: Callout failed: ' + ce.getMessage());
            return null;
        }

        if (res.getStatusCode() == 200) {
            Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> records = (List<Object>) jsonResponse.get('records');
            if (records != null && !records.isEmpty()) {
                Map<String, Object> pbeRecord = (Map<String, Object>) records[0];
                return pbeRecord;
            } else {
                System.debug('getPricebookEntryData: No PricebookEntry found for productId: ' + productId);
                return null;
            }
        } else {
            System.debug('getPricebookEntryData: Failed to query PricebookEntry. Status: ' + res.getStatusCode() + ' Body: ' + res.getBody());
            return null;
        }
    }

    /**
     * Generic helper method to fetch JSON content from an external URL.
     * @param url The full URL to make the GET request to.
     * @param accessToken The OAuth access token.
     * @return The JSON string response body, or null if failed.
     */
    private static String getExternalJsonByUrl(String url, String accessToken) {
        if (String.isBlank(url) || String.isBlank(accessToken)) {
            System.debug('getExternalJsonByUrl: url or accessToken is blank.');
            return null;
        }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Content-Type', 'application/json');
        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (System.CalloutException ce) {
            System.debug('getExternalJsonByUrl: Callout failed: ' + ce.getMessage());
           return null;
        }
        if (res != null && res.getStatusCode() == 200) {
            return res.getBody();
        } else {
            System.debug('getExternalJsonByUrl: Failed to fetch JSON. Status: ' + (res != null ? String.valueOf(res.getStatusCode()) : 'No Response') + ' Body: ' + (res != null ? res.getBody() : 'N/A'));
            return null;
        }
    }

    // This method was previously public but is now private as it's not intended to be called directly by LWC
    // and its logic is now incorporated into getOrdersAndDetailsByEmail.
    private Account ensureLocalAccount(String externalAccountId, String accessToken) {
        if(String.isBlank(externalAccountId)){
            System.debug('External Account ID is blank in ensureLocalAccount.');
            return null;
        }
        System.debug('Fetching external account data for ID: ' + externalAccountId);
        if(String.isBlank(accessToken)){
            System.debug('Access token is missing, cannot fetch external account.');
            return null;
        }
        String accountJson = getExternalRecordJsonById(ACCOUNT_ENDPOINT, externalAccountId, accessToken);
        if(String.isNotBlank(accountJson)){
            System.debug('External Account JSON: ' + accountJson);
            try{
                Map<String, Object> externalAccountData = (Map<String, Object>) JSON.deserializeUntyped(accountJson);
                if (externalAccountData != null) {
                    System.debug('External Account Data: ' + externalAccountData);
                    return null; // Not saving locally anymore as per original logic comment
                } else {
                    System.debug('Deserialized external account data is null for ID: ' + externalAccountId);
                    return null;
                }
            } catch(Exception e){
                System.debug('Failed to deserialize external account data for ID: ' + externalAccountId + '. Error: ' + e.getMessage());
                return null;
            }
        } else {
            System.debug('Failed to fetch external account data for ID: ' + externalAccountId);
            return null;
        }
    }

    // The printExternalOrderDetails method is primarily for System.debug output
    // and not suitable for direct LWC consumption as it doesn't return structured data.
    // Its logic is incorporated into getOrdersAndDetailsByEmail if relevant for LWC display.
    public static void printExternalOrderDetails(String externalOrderId, String accessToken) {
        String orderJson = getExternalRecordJsonById(EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/Order/', externalOrderId, accessToken);
        System.debug('Order Details JSON: ' + orderJson);

        String orderItemsJson = getExternalOrderItemsJson(externalOrderId, accessToken);
        System.debug('Order Items JSON: ' + orderItemsJson);
        if (String.isNotBlank(orderItemsJson)) {
            try {
                List<Object> orderItems = (List<Object>) JSON.deserializeUntyped(orderItemsJson);
                for (Object item : orderItems) {
                    System.debug('Order Item: ' + JSON.serialize(item));
                    // Fetch and log product details for each product in order items
                    Map<String, Object> itemMap = (Map<String, Object>) item;
                    if(itemMap.containsKey('Product2Id') && itemMap.get('Product2Id') != null){
                        String productId = (String) itemMap.get('Product2Id');
                        String productJson = getExternalRecordJsonById(PRODUCT_ENDPOINT, productId, accessToken);
                        System.debug('Product Details JSON for Product2Id ' + productId + ': ' + productJson);
                    }
                }
            } catch (Exception e) {
                System.debug('Failed to deserialize order items JSON: ' + e.getMessage());
            }
        }
    }

    /**
     * Deletes an external order by its ID.
     * @param externalOrderId The ID of the external order to delete.
     * @return True if deletion was successful, false otherwise.
     */
    @AuraEnabled(cacheable=false)
    public static Boolean deleteExternalOrder(String externalOrderId) {
        if (String.isBlank(externalOrderId)) {
            System.debug('deleteExternalOrder: externalOrderId is blank.');
            return false;
        }
        String accessToken = authenticate();
        if (accessToken == null) {
            System.debug('deleteExternalOrder: Authentication failed.');
            return false;
        }
        String endpoint = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/Order/' + externalOrderId;
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('DELETE');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Content-Type', 'application/json');
        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (System.CalloutException ce) {
            System.debug('deleteExternalOrder: Callout failed: ' + ce.getMessage());
            return false;
        }
        if (res.getStatusCode() == 204) {
            System.debug('deleteExternalOrder: Successfully deleted order ' + externalOrderId);
            return true;
        } else {
            System.debug('deleteExternalOrder: Failed to delete order. Status: ' + res.getStatusCode() + ' Body: ' + res.getBody());
            return false;
        }
    }

    /**
     * Deletes an external OrderItem by its external Id.
     * @param externalOrderItemId The Id of the external OrderItem to delete.
     * @return True if deletion was successful, false otherwise.
     */
    @AuraEnabled(cacheable=false)
    public static Boolean deleteExternalOrderItem(String externalOrderItemId) {
        // This method deletes an OrderItem in the external org, not local.
        if (String.isBlank(externalOrderItemId)) {
            System.debug('deleteExternalOrderItem: externalOrderItemId is blank.');
            return false;
        }
        String accessToken = authenticate();
        if (accessToken == null) {
            System.debug('deleteExternalOrderItem: Authentication failed.');
            return false;
        }
        String endpoint = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/OrderItem/' + externalOrderItemId;
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('DELETE');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Content-Type', 'application/json');
        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (System.CalloutException ce) {
            System.debug('deleteExternalOrderItem: Callout failed: ' + ce.getMessage());
            return false;
        }
        if (res.getStatusCode() == 204) {
            System.debug('deleteExternalOrderItem: Successfully deleted external OrderItem ' + externalOrderItemId);
            return true;
        } else {
            System.debug('deleteExternalOrderItem: Failed to delete external OrderItem. Status: ' + res.getStatusCode() + ' Body: ' + res.getBody());
            return false;
        }
    }

    /**
     * Updates the quantity of an external OrderItem by its external Id.
     * @param externalOrderItemId The Id of the external OrderItem to update.
     * @param newQuantity The new quantity value.
     * @return True if update was successful, false otherwise.
     */
    @AuraEnabled(cacheable=false)
    public static Boolean updateExternalOrderItemQuantity(String externalOrderItemId, Decimal newQuantity) {
        // This method updates an OrderItem in the external org, not local.
        if (String.isBlank(externalOrderItemId)) {
            System.debug('updateExternalOrderItemQuantity: externalOrderItemId is blank.');
            return false;
        }
        if (newQuantity == null) {
            System.debug('updateExternalOrderItemQuantity: newQuantity is null.');
            return false;
        }
        String accessToken = authenticate();
        if (accessToken == null) {
            System.debug('updateExternalOrderItemQuantity: Authentication failed.');
            return false;
        }
        String endpoint = EXTERNAL_INSTANCE_URL + '/services/data/' + API_VERSION + '/sobjects/OrderItem/' + externalOrderItemId;
        Map<String, Object> updateFields = new Map<String, Object>();
        updateFields.put('Quantity', newQuantity);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('PATCH');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(updateFields));
        Http http = new Http();
        HttpResponse res;
        try {
            res = http.send(req);
        } catch (System.CalloutException ce) {
            System.debug('updateExternalOrderItemQuantity: Callout failed: ' + ce.getMessage());
            return false;
        }
        if (res.getStatusCode() == 204) {
            System.debug('updateExternalOrderItemQuantity: Successfully updated quantity for external OrderItem ' + externalOrderItemId);
            return true;
        } else {
            System.debug('updateExternalOrderItemQuantity: Failed to update quantity. Status: ' + res.getStatusCode() + ' Body: ' + res.getBody());
            return false;
        }
    }
}