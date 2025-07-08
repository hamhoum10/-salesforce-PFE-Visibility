global class GDPRForgetMeBatch implements Database.Batchable<SObject>, Database.Stateful {
    //for folow
      @InvocableMethod(label='Start GDPR Forget Me Batch' description='Initiates the GDPRForgetMeBatch Apex batch job.')
    public static void startGDPRBatch() {
        GDPRForgetMeBatch forgetMeBatch = new GDPRForgetMeBatch();
        Database.executeBatch(forgetMeBatch);
    }
    //
    private static final String MASK_VALUE = 'ff';
    private Map<String, List<GDPR_Field_Cleanup__mdt>> metadataByObject;
    private List<String> objectNames;
    public Integer currentObjectIndex;

    public GDPRForgetMeBatch() {
        metadataByObject = new Map<String, List<GDPR_Field_Cleanup__mdt>>();
        for (GDPR_Field_Cleanup__mdt meta : [
            SELECT Field_API_Name__c, Anonymization_Type__c, Object_Name__c 
            FROM GDPR_Field_Cleanup__mdt
        ]) {
            if (!metadataByObject.containsKey(meta.Object_Name__c)) {
                metadataByObject.put(meta.Object_Name__c, new List<GDPR_Field_Cleanup__mdt>());
            }
            metadataByObject.get(meta.Object_Name__c).add(meta);
        }
        objectNames = new List<String>(metadataByObject.keySet());
        currentObjectIndex = 0;
    }

    global Database.QueryLocator start(Database.BatchableContext batchContext) {
        if (!objectNames.isEmpty()) {
            String objectName = objectNames[currentObjectIndex];
            String query;

            
                query = 'SELECT Id FROM ' + objectName +
                        ' WHERE ContactId IN ( SELECT Id  FROM Contact WHERE Individual.ShouldForget = true)';
            

            return Database.getQueryLocator(query);
        }

        // Dummy query to satisfy method signature
        return Database.getQueryLocator('SELECT Id FROM Account WHERE Id = null');
    }

    global void execute(Database.BatchableContext batchContext, List<SObject> recordList) {
        if (currentObjectIndex >= objectNames.size()) {
            return;
        }

        String objectName = objectNames[currentObjectIndex];
        List<GDPR_Field_Cleanup__mdt> metadataList = metadataByObject.get(objectName);
        List<SObject> toUpdate = new List<SObject>();

        if (metadataList != null) {
            for (SObject record : recordList) {
                Boolean updated = false;

                for (GDPR_Field_Cleanup__mdt meta : metadataList) {
                    Boolean changed = anonymizeField(record, meta);
                    if (changed) updated = true;
                }

                if (updated) {
                    toUpdate.add(record);
                }
            }

            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }
        }

        currentObjectIndex++;
    }

    private Boolean anonymizeField(SObject record, GDPR_Field_Cleanup__mdt meta) {
        try {
            if (meta.Anonymization_Type__c == 'Mask') {
                record.put(meta.Field_API_Name__c, MASK_VALUE);
                return true;
            } else if (meta.Anonymization_Type__c == 'Null' || meta.Anonymization_Type__c == 'Delete') {
                record.put(meta.Field_API_Name__c, null);
                return true;
            }
        } catch (Exception e) {
            System.debug('Error anonymizing field: ' + meta.Field_API_Name__c + ' - ' + e.getMessage());
        }
        return false;
    }

    global void finish(Database.BatchableContext batchContext) {
        if (currentObjectIndex + 1 < objectNames.size()) {
            GDPRForgetMeBatch nextBatch = new GDPRForgetMeBatch();
            nextBatch.currentObjectIndex = this.currentObjectIndex + 1;
            Database.executeBatch(nextBatch);
        } else {
            System.debug('GDPR Forget Me Batch Completed for all objects.');
        }
    }
}