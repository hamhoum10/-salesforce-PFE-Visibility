@isTest
private class CaseSelectorTest {
    @testSetup
    static void setupTestData() {
        Case c = new Case(Subject = 'Test Case');
        insert c;
    }

    @isTest
    static void testSelectById() {
        List<Case> cases = CaseSelector.selectById([SELECT Id FROM Case LIMIT 1][0].Id);
        System.assert(!cases.isEmpty(), 'Should return cases for existing Id');
        System.assertEquals('Test Case', cases[0].Subject);
    }
}