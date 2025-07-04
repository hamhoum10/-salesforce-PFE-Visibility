public with sharing class EcommerceServiceFactory {
    private static Map<String, Object> serviceCache = new Map<String, Object>();

    public static Object getService(String serviceTypeName) {
        if (String.isBlank(serviceTypeName)) {
            throw new EcommerceException('Service Type Name cannot be blank.');
        }

        return getServiceInstance(serviceTypeName);
    }

    /**
     * @description Retrieves or creates an instance of the requested service based on configuration.
     * @param serviceTypeName The name of the service type requested.
     * @return An instance of the requested service implementation.
     * @throws EcommerceException If configuration is missing or invalid, or if instantiation fails.
     */
    private static Object getServiceInstance(String serviceTypeName) {
        // 1. Get the active provider configuration
        String activeProvider = getActiveProvider();
        System.debug('Active Provider from Custom Setting (conectiontype__c.provider__c): \'' + activeProvider + '\', Requesting Service Type: \'' + serviceTypeName + '\'');

        // 2. Check cache first
        String cacheKey = activeProvider + ':' + serviceTypeName;
        Object cachedInstance = getFromCache(cacheKey);
        if (cachedInstance != null) {
            return cachedInstance;
        }

        // 3. Cache miss: Get configuration from Custom Metadata
        System.debug('Cache miss. Looking for service config in service_provider_config__mdt for Provider: ' + activeProvider + ', Service: ' + serviceTypeName);
        service_provider_config__mdt config = getServiceProviderConfig(activeProvider, serviceTypeName);

        // 4. Validate the retrieved configuration
        validateConfig(config, activeProvider, serviceTypeName);
        System.debug('Found config in MDT: Class Name = ' + config.class_name__c + ', Interface Name = ' + config.interface_name__c);

        // 5. Instantiate, validate, cache, and return the service instance
        return createAndValidateInstance(config.class_name__c, config.interface_name__c, cacheKey);
    }

    /**
     * @description Retrieves the active provider name from the custom setting.
     * @return The name of the active provider.
     * @throws EcommerceException If the provider is not configured in the custom setting.
     */
    private static String getActiveProvider() {
        conectiontype__c settings = conectiontype__c.getOrgDefaults();
        String activeProvider = settings?.provider__c;

        if (String.isBlank(activeProvider)) {
            System.debug('ERROR: provider__c field not set in conectiontype__c Custom Setting. Please check the Org Defaults.');
            throw new EcommerceException('Active Ecommerce Provider not configured in the provider__c field of the conectiontype__c Custom Setting.');
        }
        return activeProvider;
    }

    /**
     * @description Checks the cache for an existing service instance.
     * @param cacheKey The key to look up in the cache.
     * @return The cached service instance, or null if not found.
     */
    private static Object getFromCache(String cacheKey) {
        if (serviceCache.containsKey(cacheKey)) {
            System.debug('Returning cached service instance for key: ' + cacheKey);
            return serviceCache.get(cacheKey);
        }
        return null;
    }

    /**
     * @description Queries the service_provider_config__mdt for the configuration matching the provider and service type.
     * @param activeProvider The name of the active provider.
     * @param serviceTypeName The name of the service type.
     * @return The matching service_provider_config__mdt record.
     * @throws EcommerceException If the configuration is not found or the user lacks access.
     */
    private static service_provider_config__mdt getServiceProviderConfig(String activeProvider, String serviceTypeName) {
        List<service_provider_config__mdt> configs;
        if (Schema.sObjectType.service_provider_config__mdt.isAccessible()) {
            configs = [
                SELECT class_name__c, interface_name__c
                FROM service_provider_config__mdt
                WHERE provider__c = :activeProvider
                  AND service__c = :serviceTypeName
                LIMIT 1
            ];
        } else {
            System.debug('ERROR: User does not have access to service_provider_config__mdt.');
            throw new EcommerceException('User does not have access to service_provider_config__mdt.');
        }

        if (configs.isEmpty()) {
            System.debug('ERROR: No configuration found in service_provider_config__mdt for Provider: ' + activeProvider + ', Service: ' + serviceTypeName);
            throw new EcommerceException('Ecommerce service configuration not found in service_provider_config__mdt for Provider: ' + activeProvider + ', Service: ' + serviceTypeName);
        }
        return configs[0];
    }

    /**
     * @description Validates that the class name and interface name in the configuration are not blank.
     * @param config The configuration metadata record.
     * @param activeProvider The name of the active provider (for error messages).
     * @param serviceTypeName The name of the service type (for error messages).
     * @throws EcommerceException If class_name__c or interface_name__c is blank.
     */
    private static void validateConfig(service_provider_config__mdt config, String activeProvider, String serviceTypeName) {
        if (String.isBlank(config.class_name__c)) {
            System.debug('ERROR: Configuration found in MDT, but class_name__c is blank for Provider: ' + activeProvider + ', Service: ' + serviceTypeName);
            throw new EcommerceException('Configuration error in service_provider_config__mdt: class_name__c is blank for ' + activeProvider + '/' + serviceTypeName);
        }
        if (String.isBlank(config.interface_name__c)) {
            System.debug('ERROR: Configuration found in MDT, but interface_name__c is blank for Provider: ' + activeProvider + ', Service: ' + serviceTypeName);
            throw new EcommerceException('Configuration error in service_provider_config__mdt: interface_name__c is blank for ' + activeProvider + '/' + serviceTypeName);
        }
    }

    /**
     * @description Instantiates the service class, validates it implements the specified interface, caches it, and returns the instance.
     * @param className The name of the class to instantiate.
     * @param interfaceName The name of the interface the class should implement.
     * @param cacheKey The key to use for caching the instance.
     * @return The newly created and validated service instance.
     * @throws EcommerceException If the class or interface cannot be found, instantiation fails, or the class doesn't implement the interface.
     */
    private static Object createAndValidateInstance(String className, String interfaceName, String cacheKey) {
        Object instance = null;
        try {
            Type classType = Type.forName(className);
            Type interfaceType = Type.forName(interfaceName);

            if (classType == null) {
                System.debug('ERROR: Could not find Type for class name from MDT: ' + className);
                throw new EcommerceException('Configuration error: Class ' + className + ' (from MDT) not found.');
            }
            if (interfaceType == null) {
                System.debug('ERROR: Could not find Type for interface name from MDT: ' + interfaceName);
                throw new EcommerceException('Configuration error: Interface ' + interfaceName + ' (from MDT) not found.');
            }

            instance = classType.newInstance();

            // Verify the instance's class implements or extends the expected interface/base class
            if (instance != null && interfaceType.isAssignableFrom(classType)) {
                System.debug('Successfully instantiated and verified class ' + className + ' implements/extends ' + interfaceName);
                serviceCache.put(cacheKey, instance); // Add to cache
                return instance;
            } else {
                System.debug('ERROR: Instantiated class ' + className + ' does not implement the expected interface ' + interfaceName + ' (as defined in MDT)');
                throw new EcommerceException('Configuration error: Class ' + className + ' does not implement ' + interfaceName);
            }
        } catch (System.TypeException te) {
            System.debug('ERROR: Type error during service instantiation (MDT config). Class: ' + className + ', Interface: ' + interfaceName + '. Message: ' + te.getMessage());
            throw new EcommerceException('Configuration error: Could not find Class \'' + className + '\' or Interface \'' + interfaceName + '\' (defined in MDT). Check names and deployment.', te);
        } catch (Exception e) {
            System.debug('ERROR: Error instantiating class ' + className + ' (from MDT config). Message: ' + e.getMessage() + '\nStackTrace: ' + e.getStackTraceString());
            throw new EcommerceException('Error creating service instance for ' + className + ' (from MDT config): ' + e.getMessage(), e);
        }
    }

    // Custom Exception class remains the same
    public class EcommerceException extends Exception {}
}