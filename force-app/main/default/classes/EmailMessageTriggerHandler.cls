public class EmailMessageTriggerHandler {

   public void run() {
    List<EmailMessage> newEmailMessages = (List<EmailMessage>) Trigger.new;
    System.debug('Starting run() method. Trigger.new size: ' + (newEmailMessages != null ? newEmailMessages.size() : 0));

    if (newEmailMessages == null || newEmailMessages.isEmpty()) {
        System.debug('No new EmailMessages to process. Exiting run().');
        return;
    }

    Set<Id> parentIds = new Set<Id>();
    for (EmailMessage em : newEmailMessages) {
        if (em.ParentId != null) {
            parentIds.add(em.ParentId);
        } else {
            System.debug('EmailMessage ' + em.Id + ' has no ParentId.');
        }
    }

    if (parentIds.isEmpty()) {
        System.debug('No ParentIds found in new EmailMessages. Exiting run().');
        return;
    }

    System.debug('Collected ParentIds: ' + parentIds);

    Map<Id, String> parentIdToAiDataMap = new Map<Id, String>();

    List<EmailMessage> allRelatedEmails = [
        SELECT ParentId, TextBody, CreatedDate
        FROM EmailMessage
        WHERE ParentId IN :parentIds
        ORDER BY ParentId, CreatedDate ASC
    ];

    System.debug('Fetched ' + allRelatedEmails.size() + ' related EmailMessages.');

    for (EmailMessage relatedEmail : allRelatedEmails) {
        String currentAiData = parentIdToAiDataMap.get(relatedEmail.ParentId);
        String textBodyContent = relatedEmail.TextBody == null ? '' : relatedEmail.TextBody;

        if (currentAiData == null) {
            parentIdToAiDataMap.put(relatedEmail.ParentId, textBodyContent);
        } else {
            parentIdToAiDataMap.put(relatedEmail.ParentId, currentAiData + '\n\n' + textBodyContent);
        }
    }

    System.debug('Constructed parentIdToAiDataMap: ' + parentIdToAiDataMap);

    List<Map<String, String>> allFlowInvocationParams = new List<Map<String, String>>();

    for (EmailMessage newEmail : newEmailMessages) {
        if (newEmail.ParentId == null) {
            System.debug('EmailMessage ' + newEmail.Id + ' has no ParentId. Skipping.');
            continue;
        }

        String aidata = parentIdToAiDataMap.get(newEmail.ParentId);
        if (aidata == null) {
            System.debug('No AI data found for ParentId: ' + newEmail.ParentId);
            aidata = '';
        }

        String recipientEmail = newEmail.FromAddress;
        if (String.isBlank(recipientEmail)) {
            System.debug('EmailMessage ' + newEmail.Id + ' has no FromAddress. Skipping.');
            continue;
        }

        Map<String, String> currentFlowParams = new Map<String, String>();
        currentFlowParams.put('inputText', aidata);
        currentFlowParams.put('recipientEmail', recipientEmail);
        allFlowInvocationParams.add(currentFlowParams);

        System.debug('Prepared flow params for EmailMessage ' + newEmail.Id + ': ' + currentFlowParams);
    }

    if (!allFlowInvocationParams.isEmpty()) {
        String jsonParams = JSON.serialize(allFlowInvocationParams);
        System.debug('Invoking flow asynchronously with params: ' + jsonParams);
        invokeFlowAsynchronously(jsonParams);
    } else {
        System.debug('No flow parameters to invoke. Skipping flow call.');
    }

    System.debug('run() method completed.');
}


    @future(callout=true)
  public static void invokeFlowAsynchronously(String jsonParams) {
        // Deserialize the JSON string back to List<Map<String, String>>
        List<Map<String, String>> flowParamsList = (List<Map<String, String>>) JSON.deserialize(jsonParams, List<Map<String, String>>.class);

        for (Map<String, String> params : flowParamsList) {
            String inputText = params.get('inputText');
            String recipientEmail = params.get('recipientEmail');

            Map<String, Object> flowInputs = new Map<String, Object>();
            flowInputs.put('inputText', inputText);
            flowInputs.put('recipientEmail', recipientEmail);

            try {
                Flow.Interview flowInterview = Flow.Interview.createInterview('ai auto tesponse apex	', flowInputs);
                flowInterview.start();
            } catch (Exception e) {
                System.debug('Error invoking flow "testmail" asynchronously. Recipient: ' + recipientEmail +
                             '. Error: ' + e.getMessage() + '. StackTrace: ' + e.getStackTraceString());
                // Consider creating a Task or a custom Log object for persistent error tracking from future methods.
            }
        }
    }
}