public class refundAgent {
 public class RefundInput {
        @InvocableVariable public String externalOrderId;
        @InvocableVariable public String refundStatus;
    }

    public class RefundOutput {
        @InvocableVariable public Boolean success;
    }

    @InvocableMethod
    public static List<RefundOutput> updateRefund(List<RefundInput> inputs) {
        List<RefundOutput> results = new List<RefundOutput>();
        omri handler = new omri();
        for (RefundInput input : inputs) {
            RefundOutput result = new RefundOutput();
            result.success = handler.refund_status(input.externalOrderId, input.refundStatus);
            results.add(result);
        }
        return results;
    }
}