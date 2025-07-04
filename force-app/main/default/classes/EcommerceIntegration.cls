public with sharing class EcommerceIntegration {
    @future(callout = true)
    public static void getAccountAndContact(Id caseId, String email) {
        // Define the service type name (should match 'service__c' in MDT)
        String serviceTypeName = 'Customer Service'; // Or whatever you defined in MDT

        try {
            // Get the service instance from the factory
            ICustomerService service = (ICustomerService) EcommerceServiceFactory.getService(serviceTypeName);

            // Check if the service was successfully retrieved 
            if (service != null) {
                // Call the method on the retrieved service instance
                service.getAccountAndContact(caseId, email);
                System.debug('Successfully invoked service for type: ' + serviceTypeName);
            } else {
                 // This case might not be reachable if factory throws exceptions correctly
                 System.debug('ERROR: Failed to retrieve service for type: ' + serviceTypeName);
            }

        } catch (EcommerceServiceFactory.EcommerceException e) {
            // Catch factory-specific exceptions
            System.debug('ERROR: Factory configuration error: ' + e.getMessage());
            // Handle configuration errors (e.g., log, notify admin)
        } catch (Exception e) {
            // Catch general exceptions during service retrieval or execution
            System.debug('ERROR: Error during EcommerceIntegration execution: ' + e.getMessage() + '\nStackTrace: ' + e.getStackTraceString());
            // Handle runtime errors (e.g., log, notify admin)
        }
    }
}