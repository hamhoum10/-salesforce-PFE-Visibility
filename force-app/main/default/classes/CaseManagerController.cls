// CaseManagerController.cls
public with sharing class CaseManagerController {

    /**
     * @Description: Fetches all Case records that do not have an associated Account.
     * @Returns: List of Case records.
     */
    @AuraEnabled(cacheable=true)
    public static List<Case> getCasesWithoutAccount() {
        try {
            return [SELECT Id, CaseNumber, Subject, Status, Priority, AccountId
                    FROM Case
                    WHERE AccountId = NULL
                    ORDER BY CreatedDate DESC];
        } catch (Exception e) {
            // Log the exception for debugging purposes
            System.debug('Error in getCasesWithoutAccount: ' + e.getMessage());
            throw new AuraHandledException('Error fetching cases without account: ' + e.getMessage());
        }
    }
    @AuraEnabled(cacheable=true)
public static List<Case> getLinkedCases() {
    try {
        return [SELECT Id, CaseNumber, Subject, Status, Priority, AccountId, Account.Name // Add Account.Name for display
                FROM Case
                WHERE AccountId != NULL
                ORDER BY CreatedDate DESC];
    } catch (Exception e) {
        System.debug('Error in getLinkedCases: ' + e.getMessage());
        throw new AuraHandledException('Error fetching linked cases: ' + e.getMessage());
    }
}

    /**
     * @Description: Updates the AccountId for a given Case record.
     * @Param caseId: The Id of the Case to update.
     * @Param accountId: The Id of the Account to link to the Case.
     * @Returns: True if the update was successful, false otherwise.
     */
    @AuraEnabled
    public static Boolean linkAccountToCase(String caseId, String accountId) {
        try {
            Case caseToUpdate = new Case(Id = caseId, AccountId = accountId);
            update caseToUpdate;
            return true;
        } catch (Exception e) {
            // Log the exception for debugging purposes
            System.debug('Error in linkAccountToCase: ' + e.getMessage());
            throw new AuraHandledException('Error linking account to case: ' + e.getMessage());
        }
    }
    public with sharing class AccountSearchController {
    @AuraEnabled(cacheable=true)
    public static List<Account> searchAccounts(String searchTerm) {
        String searchWildcard = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        return [SELECT Id, Name, PersonEmail, Phone // Assuming Person Accounts or similar email field
                FROM Account
                WHERE Name LIKE :searchWildcard
                OR PersonEmail LIKE :searchWildcard
                OR Phone LIKE :searchWildcard
                LIMIT 50]; // Limit results for performance
    }
}