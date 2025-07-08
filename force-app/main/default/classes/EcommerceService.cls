public with sharing class EcommerceService implements ICustomerService {
    private static final String AUTH_URL = 'https://login.salesforce.com/services/oauth2/token';
    private static final String ENDPOINT_QUERY = 'https://pwcsandbox53-dev-ed.develop.my.salesforce.com/services/data/v63.0/query';
    private static final String ENDPOINT_SOBJECT = 'https://pwcsandbox53-dev-ed.develop.my.salesforce.com/services/data/v47.0/sobjects/Account/';


    public static void getAccountAndContact(Id caseId, String email) {
        try {
            String accessToken = authenticate();
            if (accessToken != null) {
                callEcommerceApi(caseId, email, accessToken);
            }
        } catch (Exception e) {
            System.debug('Error in getAccountAndContact: ' + e.getMessage());
        }
    }

    public static String authenticate() {
        String clientId = System.Label.OAuth_Client_ID;
        String clientSecret = System.Label.OAuth_Client_Secret;
        String username = System.Label.OAuth_Username;
        String password = System.Label.OAuth_Password;

        HttpRequest authRequest = new HttpRequest();
        authRequest.setEndpoint(AUTH_URL);
        authRequest.setMethod('POST');
        authRequest.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        authRequest.setBody(
            'grant_type=password' +
            '&client_id=' + EncodingUtil.urlEncode(clientId, 'UTF-8') +
            '&client_secret=' + EncodingUtil.urlEncode(clientSecret, 'UTF-8') +
            '&username=' + EncodingUtil.urlEncode(username, 'UTF-8') +
            '&password=' + EncodingUtil.urlEncode(password, 'UTF-8')
        );

        Http http = new Http();
        HttpResponse authResponse = null;
        try {
             authResponse = http.send(authRequest);
        } catch(System.CalloutException ce) {
            System.debug('Authentication callout failed: ' + ce.getMessage());
            return null;
        }


        if (authResponse != null && authResponse.getStatusCode() == 200) {
            Map<String, Object> authResult = (Map<String, Object>) JSON.deserializeUntyped(authResponse.getBody());
            return (String) authResult.get('access_token');
        } else {
            System.debug('Authentication failed: ' + (authResponse != null ? authResponse.getBody() : 'No Response'));
            return null;
        }
    }

    public static void callEcommerceApi(Id caseId, String email, String accessToken) {
        String query = 'SELECT+Id+FROM+Account+WHERE+PersonEmail=\'' + EncodingUtil.urlEncode(email, 'UTF-8') + '\'';
        String endpoint = ENDPOINT_QUERY + '?q=' + query;

        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('GET');
        request.setHeader('Authorization', 'Bearer ' + accessToken);
        request.setHeader('Content-Type', 'application/json');

        Http http = new Http();
        HttpResponse response = null;
        try {
            response = http.send(request);
        } catch(System.CalloutException ce) {
             System.debug('External Account query callout failed: ' + ce.getMessage());
             return;
        }


        if (response != null && response.getStatusCode() == 200) {
            Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            List<Object> records = (List<Object>) result.get('records');
            if (records != null && !records.isEmpty()) {
                for (Object o : records) {
                    Map<String, Object> record = (Map<String, Object>) o;
                    String externalAccountId = (String) record.get('Id');
                    if (externalAccountId != null) {
                        Map<String, Object> accountDetails = getAccountDetailsById(externalAccountId, accessToken);
                        if (accountDetails != null) {
                            upsertAccountAndContact(caseId, accountDetails);
                        } else {
                            System.debug('No account details found for external Id: ' + externalAccountId);
                        }
                    }
                }
            } else {
                System.debug('No external records found for email: ' + email);
            }
        } else {
            System.debug('External API call failed: ' + (response != null ? response.getBody() : 'No Response'));
        }
    }

    public static Map<String, Object> getAccountDetailsById(String accountId, String accessToken) {
        String endpoint = ENDPOINT_SOBJECT + accountId;
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('GET');
        request.setHeader('Authorization', 'Bearer ' + accessToken);
        request.setHeader('Content-Type', 'application/json');

        Http http = new Http();
        HttpResponse response = null;
        try {
            response = http.send(request);
        } catch(System.CalloutException ce) {
            System.debug('Get Account Details callout failed for Id ' + accountId + ': ' + ce.getMessage());
            return null;
        }


        if (response != null && response.getStatusCode() == 200) {
            return (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        } else {
            System.debug('API call failed for get account details by Id: ' + (response != null ? response.getBody() : 'No Response'));
            return null;
        }
    }

    public static void upsertAccountAndContact(Id caseId, Map<String, Object> data) {
        try {
            String externalId = (String) data.get('Id');
            if(String.isBlank(externalId)){
                System.debug('External Id missing from data payload. Cannot upsert Account.');
                return;
            }

            List<Account> existingAccounts = AccountSelector.selectByExternalId(externalId);
            Account acc;
            Individual ind;
            Boolean isUpdate = !existingAccounts.isEmpty();

            if (isUpdate) {
                acc = existingAccounts[0];
                acc.PersonEmail = (String) data.get('PersonEmail');
                acc.Phone = (String) data.get('Phone');

                update acc;
                System.debug('Person Account updated ' + acc.Id);
            } else {
                
                // Get the default record type for Personal Accounts
                RecordType personalRt = [
                    SELECT Id 
                    FROM RecordType 
                    WHERE SObjectType = 'Account' 
                    AND IsPersonType = true 
                    LIMIT 1
                ];
                ind = new Individual();
                 ind.LastName = (String) data.get('LastName');
                ind.FirstName = (String) data.get('FirstName');
                insert ind;
                System.debug('Person Individual inserted ' + ind.Id);

                acc = new Account();  
                acc.RecordTypeId = personalRt.Id;
                acc.LastName = (String) data.get('LastName');
                acc.FirstName = (String) data.get('FirstName');
                acc.PersonEmail = (String) data.get('PersonEmail');
                acc.Phone = (String) data.get('Phone');
                acc.External_id__c = externalId;
                acc.PersonIndividualId = ind.Id ; 
                insert acc;
                System.debug('Person Account inserted ' + acc.Id);
            }

            List<Case> caseList = CaseSelector.selectById(caseId);
            if (!caseList.isEmpty()) {
                Case c = caseList[0];
                c.AccountId = acc.Id;

                // Re-query the account if it was inserted to get the PersonContactId reliably
                // Or ensure PersonContactId was queried by the selector if needed earlier
                if(acc.PersonContactId == null && !isUpdate) {
                    List<Account> insertedAcc = AccountSelector.selectByExternalId(externalId);
                    if(!insertedAcc.isEmpty()){
                        acc = insertedAcc[0];
                    }
                }

                if(acc.PersonContactId != null) {
                     c.ContactId = acc.PersonContactId;
                }

                update c;
                System.debug('Updated Case: ' + c.Id);
            } else {
                System.debug('No Case found with Id: ' + caseId);
            }
        } catch (Exception e) {
            System.debug('Error in upsertAccountAndContact: ' + e.getMessage() + '\nStackTrace: ' + e.getStackTraceString());
        }
    }
}