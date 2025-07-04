public with sharing class getExternalAccountAgent {
    
    public class Request {
        @InvocableVariable(required=true)
        public Id caseId;

        @InvocableVariable(required=true)
        public String email;
    }

    public with sharing class Response {
         @InvocableVariable
        public String message;

        @InvocableVariable
        public Id accountId;

        @InvocableVariable
        public String accountName;

        @InvocableVariable
        public String phone;

        @InvocableVariable
        public String email;
    }

    @InvocableMethod(label='Fetch External Account and Contact')
    public static List<Response> invoke(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request req : requests) {
            Response r = new Response();
            try {
              
                 
               EcommerceService.getAccountAndContact(req.caseId, req.email);

                // re-fetch account via Case link
                
                Case c = [SELECT Account.Id, Account.Name, Account.Phone, Account.PersonEmail 
                          FROM Case WHERE Id =: req.caseId LIMIT 1];
                r.accountId = c.AccountId;
                r.accountName = c.Account.Name;
                r.phone = c.Account.Phone;
                r.email = c.Account.PersonEmail;
                r.message = 'Success';
                
            } catch (Exception e) {
                r.message = 'Error: ' + e.getMessage();
            }
            responses.add(r);
        }

        return responses;
    }
}