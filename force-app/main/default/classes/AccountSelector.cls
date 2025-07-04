public with sharing class AccountSelector {
    public static List<Account> selectByExternalId(String externalId) {
        if (String.isBlank(externalId)) {
            return new List<Account>();
        }
        try {
            return [
                SELECT Id, External_id__pc, PersonContactId
                FROM Account
                WHERE External_id__c = :externalId

                LIMIT 1
            ];
        } catch (System.QueryException e) {
            System.debug('AccountSelector query failed: ' + e.getMessage());
            return new List<Account>();
        }
    }
}