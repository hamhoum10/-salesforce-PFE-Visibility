trigger emailmessageTriger on EmailMessage (before insert) {
    Set<Id> parentIds = new Set<Id>();
    for (EmailMessage em : Trigger.new) {
        if (em.ParentId != null) {
            parentIds.add(em.ParentId);
        }
    }

    // Query existing EmailMessages with matching ParentIds
    Map<Id, List<EmailMessage>> parentToEmails = new Map<Id, List<EmailMessage>>();
    for (EmailMessage em : [
        SELECT ParentId, TextBody 
        FROM EmailMessage 
        WHERE ParentId IN :parentIds
    ]) {
        if (!parentToEmails.containsKey(em.ParentId)) {
            parentToEmails.put(em.ParentId, new List<EmailMessage>());
        }
        parentToEmails.get(em.ParentId).add(em);
    }

    for (EmailMessage em : Trigger.new) {
        List<EmailMessage> relatedEmails = parentToEmails.get(em.ParentId);
        String fullDescription = '';
        if (relatedEmails != null) {
            for (EmailMessage related : relatedEmails) {
                fullDescription += related.TextBody + '\n\n';
            }
        }
        System.enqueueJob(new EmailHandlerAsync(em.Subject, em.FromAddress, fullDescription));
    }
}