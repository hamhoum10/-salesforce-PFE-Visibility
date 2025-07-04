@isTest
private class OrderServiceTest {
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            if (req.getEndpoint().contains('/services/oauth2/token')) {
                res.setBody('{"access_token":"mock_access_token"}');
                res.setStatusCode(200);
            } else if (req.getEndpoint().contains('/sobjects/Order/')) {
                res.setBody('{"Id":"mockOrderId","OrderNumber":"12345","Status":"Activated","EffectiveDate":"2023-01-01"}');
                res.setStatusCode(200);
            } else if (req.getEndpoint().contains('/query?q=SELECT+Id,OrderId,Product2Id,Quantity,UnitPrice+FROM+OrderItem')) {
                res.setBody('{"records":[{"Id":"mockItemId","OrderId":"mockOrderId","Product2Id":"mockProdId","Quantity":2,"UnitPrice":100.0}]}');
                res.setStatusCode(200);
            } else if (req.getEndpoint().contains('/sobjects/Product2/')) {
                res.setBody('{"Id":"mockProdId","Name":"Test Product","ProductCode":"TP001","Description":"Test product description"}');
                res.setStatusCode(200);
            } else if (req.getEndpoint().contains('/sobjects/Account/')) {
                res.setBody('{"Id":"mockAccountId","Name":"Test Account"}');
                res.setStatusCode(200);
            } else {
                res.setBody('{}');
                res.setStatusCode(200);
            }
            return res;
        }
    }

    @testSetup
    static void setupTestData() {
        // Create test data needed for the test, e.g., Pricebook2 standard pricebook
        Pricebook2 standardPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        if (standardPb == null) {
            standardPb = new Pricebook2(Name='Standard Pricebook', IsActive=true);
            insert standardPb;
        }
    }

    @isTest
    static void testSyncOrderData_Success() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        OrderService service = new OrderService();

        Test.startTest();
        service.syncOrderData('mockOrderId', 'mockAccountId');
        Test.stopTest();

        // Verify that local Account, Contract, Product2, PricebookEntry, Order, and OrderItem records were created or updated
        Account acc = [SELECT Id, External_Id__c FROM Account WHERE External_Id__c = 'mockAccountId' LIMIT 1];
        System.assertNotEquals(null, acc, 'Account should be created or found');

        Contract contract = [SELECT Id, AccountId FROM Contract WHERE AccountId = :acc.Id LIMIT 1];
        System.assertNotEquals(null, contract, 'Contract should be created or found');

        Product2 prod = [SELECT Id, External_Id__c FROM Product2 WHERE External_Id__c = 'mockProdId' LIMIT 1];
        System.assertNotEquals(null, prod, 'Product2 should be created or found');

        Order ord = [SELECT Id, External_Id__c FROM Order WHERE External_Id__c = 'mockOrderId' LIMIT 1];
        System.assertNotEquals(null, ord, 'Order should be created or found');

        OrderItem item = [SELECT Id, External_Id__c FROM OrderItem WHERE External_Id__c = 'mockItemId' LIMIT 1];
        System.assertNotEquals(null, item, 'OrderItem should be created or found');
    }

    @isTest
    static void testSyncOrderData_InvalidInput() {
        OrderService service = new OrderService();

        Test.startTest();
        service.syncOrderData(null, null);
        service.syncOrderData('', '');
        Test.stopTest();

        // No exceptions should be thrown, and no records created
        Integer accCount = [SELECT count() FROM Account];
        System.assert(accCount == 0, 'No Account should be created for invalid input');
    }
}