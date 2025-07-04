public with sharing class CaseSelector {
    public static List<Case> selectById(Id caseId) {
        if (caseId == null) {
            return new List<Case>();
        }
        try {
            return [
                SELECT Id, AccountId, ContactId
                FROM Case
                WHERE Id = :caseId

                LIMIT 1
            ];
        } catch (System.QueryException e) {
            System.debug('CaseSelector query failed: ' + e.getMessage());
            return new List<Case>();
        }
    }
}