public with sharing class getOrderInfoAgent {

    public class Request {
        @InvocableVariable(required=true)
        public String email;
    }

    public class Response {
        public String orderId;
        public String totalAmount;
        public String refundStatus;
        public String effectiveDate;
    }

    public class ResponseWrapper {
        @InvocableVariable
        public List<Response> EXternalOrder;

        @InvocableVariable
        public String summary; // Added summary field for chat display
    }

    @InvocableMethod(label='Get Orders by Email' description='Returns order info for a given email')
    public static List<ResponseWrapper> getOrders(List<Request> requests) {
        List<ResponseWrapper> wrappedResults = new List<ResponseWrapper>();
        List<Response> results = new List<Response>();

        if (requests == null || requests.isEmpty()) return wrappedResults;

        String email = requests[0].email;
        if (String.isBlank(email)) return wrappedResults;

        String accessToken = omri.authenticate();
        if (accessToken == null) return wrappedResults;

        String soql = 'SELECT Id, TotalAmount, Refund_Status__c, EffectiveDate FROM Order WHERE Account.PersonEmail = \'' + String.escapeSingleQuotes(email) + '\'';
        String queryEndpoint = omri.EXTERNAL_INSTANCE_URL + '/services/data/' + omri.API_VERSION + '/query?q=' + EncodingUtil.urlEncode(soql, 'UTF-8');

        HttpRequest httpReq = new HttpRequest();
        httpReq.setEndpoint(queryEndpoint);
        httpReq.setMethod('GET');
        httpReq.setHeader('Authorization', 'Bearer ' + accessToken);
        httpReq.setHeader('Content-Type', 'application/json');

        try {
            Http http = new Http();
            HttpResponse res = http.send(httpReq);
            if (res.getStatusCode() == 200) {
                Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                List<Object> records = (List<Object>) jsonResponse.get('records');

                for (Object recordObj : records) {
                    Map<String, Object> order = (Map<String, Object>) recordObj;

                    Response r = new Response();
                    r.orderId = (String) order.get('Id');
                    r.totalAmount = String.valueOf(order.get('TotalAmount'));
                    r.refundStatus = (String) order.get('Refund_Status__c');
                    r.effectiveDate = (String) order.get('EffectiveDate');

                    results.add(r);
                }
            }
        } catch (Exception e) {
            System.debug('Order retrieval failed: ' + e.getMessage());
        }

        // Build summary string for chat
        String summary = 'Here are the external orders for the customer:\n';
        for (Response r : results) {
            summary += '- Order ID: ' + r.orderId +
                       ', Total: ' + r.totalAmount +
                       ', Refund Status: ' + r.refundStatus +
                       ', Effective Date: ' + r.effectiveDate + '\n';
        }

        ResponseWrapper wrapper = new ResponseWrapper();
        wrapper.EXternalOrder = results;
        wrapper.summary = summary;
        wrappedResults.add(wrapper);

        return wrappedResults;
    }
}