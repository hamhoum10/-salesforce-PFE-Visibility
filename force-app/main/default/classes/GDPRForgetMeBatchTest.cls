@isTest
private class GDPRForgetMeBatchTest {
    @testSetup
    static void setupTestData() {
        // Create test metadata records for GDPR_Field_Cleanup__mdt
        List<GDPR_Field_Cleanup__mdt> mdts = new List<GDPR_Field_Cleanup__mdt>{
            new GDPR_Field_Cleanup__mdt(
                DeveloperName = 'TestFieldMask',
                Field_API_Name__c = 'Phone',
                Anonymization_Type__c = 'Mask',
                Object_Name__c = 'Contact'
            ),
            new GDPR_Field_Cleanup__mdt(
                DeveloperName = 'TestFieldNull',
                Field_API_Name__c = 'Email',
                Anonymization_Type__c = 'Null',
                Object_Name__c = 'Contact'
            )
        };
        

        // Create Contact with ShouldForget = true
        Contact c = new Contact(LastName = 'Test', Phone = '1234567890', Email = 'test@example.com');
        insert c;

        // Create related SObject records to be anonymized
        Account a = new Account(Name = 'Test Account');
        insert a;
    }

    @isTest
    static void testBatchExecution() {
        GDPRForgetMeBatch batch = new GDPRForgetMeBatch();

        Test.startTest();
        Database.executeBatch(batch, 1);
        Test.stopTest();

        // Verify that Contact fields were anonymized
        Contact c = [SELECT Phone, Email FROM Contact WHERE LastName = 'Test' LIMIT 1];
        System.assertEquals('ff', c.Phone, 'Phone should be masked');
        System.assertEquals(null, c.Email, 'Email should be nullified');
    }

    @isTest
    static void testAnonymizeField() {
        GDPRForgetMeBatch batch = new GDPRForgetMeBatch();

        Contact c = new Contact(LastName = 'Dummy');
        GDPR_Field_Cleanup__mdt maskMeta = new GDPR_Field_Cleanup__mdt(Field_API_Name__c = 'Phone', Anonymization_Type__c = 'Mask');
        GDPR_Field_Cleanup__mdt nullMeta = new GDPR_Field_Cleanup__mdt(Field_API_Name__c = 'Email', Anonymization_Type__c = 'Null');

        // Boolean masked = batch.anonymizeField(c, maskMeta);
        // Boolean nulled = batch.anonymizeField(c, nullMeta);

        // System.assert(masked, 'Field should be masked');
        // System.assert(nulled, 'Field should be nullified');
        System.assertEquals('ff', c.Phone, 'Phone should be masked');
        System.assertEquals(null, c.Email, 'Email should be nullified');
    }
}