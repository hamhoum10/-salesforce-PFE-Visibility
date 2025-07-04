@isTest
private class AccountSelectorTest {
    @testSetup
    static void setupTestData() {
        Account acc = new Account(Name = 'Test Account', External_Id__c = 'ext123');
        insert acc;
    }

    @isTest
    static void testSelectByExternalId() {
        List<Account> accounts = AccountSelector.selectByExternalId('ext123');
        System.assert(!accounts.isEmpty(), 'Should return accounts for existing external ID');
        System.assertEquals('Test Account', accounts[0].Name);
    }
}