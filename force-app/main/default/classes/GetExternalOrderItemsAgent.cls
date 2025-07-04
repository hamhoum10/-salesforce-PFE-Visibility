public with sharing class GetExternalOrderItemsAgent {

    public class Request {
        @InvocableVariable(required=true)
        public String externalOrderId;
    }

    public class Response {
        public String orderItemId;
        public String productName;
        public String quantity;
        public String unitPrice;
    }

    public class ResponseWrapper {
        @InvocableVariable
        public List<Response> externalOrderItems;

        @InvocableVariable
        public String summary;
    }

    @InvocableMethod(label='Get External Order Items' description='Returns order item info with product names for a given external order ID')
    public static List<ResponseWrapper> getOrderItems(List<Request> requests) {
        List<ResponseWrapper> wrappedResults = new List<ResponseWrapper>();
        List<Response> results = new List<Response>();

        if (requests == null || requests.isEmpty()) return wrappedResults;

        String externalOrderId = requests[0].externalOrderId;
        if (String.isBlank(externalOrderId)) return wrappedResults;

        String accessToken = omri.authenticate();
        if (String.isBlank(accessToken)) {
            System.debug('Authentication failed.');
            return wrappedResults;
        }

        String soql = 'SELECT Id, Product2Id, Quantity, UnitPrice FROM OrderItem WHERE OrderId = \'' + String.escapeSingleQuotes(externalOrderId) + '\'';
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
                    Map<String, Object> item = (Map<String, Object>) recordObj;

                    String productId = (String) item.get('Product2Id');
                    String productName = fetchProductName(productId, accessToken);

                    Response r = new Response();
                    r.orderItemId = (String) item.get('Id');
                    r.productName = productName;
                    r.quantity = String.valueOf(item.get('Quantity'));
                    r.unitPrice = String.valueOf(item.get('UnitPrice'));

                    results.add(r);
                }
            }
        } catch (Exception e) {
            System.debug('Order item retrieval failed: ' + e.getMessage());
        }

        // Build summary string for chat
        String summary = 'Here are the external order items:\n';
        for (Response r : results) {
            summary += '- Item ID: ' + r.orderItemId +
                       ', Product: ' + r.productName +
                       ', Quantity: ' + r.quantity +
                       ', Unit Price: ' + r.unitPrice + '\n';
        }

        ResponseWrapper wrapper = new ResponseWrapper();
        wrapper.externalOrderItems = results;
        wrapper.summary = summary;
        wrappedResults.add(wrapper);

        return wrappedResults;
    }

    private static String fetchProductName(String productId, String accessToken) {
        if (String.isBlank(productId)) return 'Unknown Product';

        String endpoint = omri.PRODUCT_ENDPOINT + '/' + productId;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + accessToken);
        req.setHeader('Content-Type', 'application/json');

        try {
            Http http = new Http();
            HttpResponse res = http.send(req);
            if (res.getStatusCode() == 200) {
                Map<String, Object> product = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                return (String) product.get('Name');
            } else {
                System.debug('Failed to fetch product name for ID: ' + productId);
            }
        } catch (Exception e) {
            System.debug('Product name fetch failed: ' + e.getMessage());
        }

        return 'Unknown Product';
    }
}