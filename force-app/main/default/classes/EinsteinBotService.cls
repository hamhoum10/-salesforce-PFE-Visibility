public with sharing class EinsteinBotService {

    /**
     * Represents the response structure from the Einstein Bot API for a single message interaction.
     */
    public class BotApiResponse {
        @AuraEnabled public String conversationId;
        @AuraEnabled public String messageText;
        // You can add more fields here if your bot returns structured data
        // For example:
        // @AuraEnabled public List<String> quickReplyOptions;
        // @AuraEnabled public Map<String, Object> customData;

        public BotApiResponse(String convId, String msgText) {
            this.conversationId = convId;
            this.messageText = msgText;
        }
    }

    /**
     * Starts a new conversation with the Einstein Bot.
     * @param botId The ID of the Einstein Bot.
     * @param initialMessage The first message to send to the bot.
     * @param contextVariables A map of variables to pass to the bot at the start of the conversation.
     * @return A BotApiResponse object containing the conversationId and the bot's initial message.
     */
    @AuraEnabled(cacheable=false) // Must be false for DML/external calls
    public static BotApiResponse startNewBotConversation(String botId, String initialMessage, Map<String, Object> contextVariables) {
        return sendBotMessage(botId, null, initialMessage, contextVariables); // Null conversationId for new conversation
    }

    /**
     * Sends a message to an ongoing Einstein Bot conversation.
     * @param botId The ID of the Einstein Bot.
     * @param conversationId The ID of the ongoing conversation.
     * @param message The message to send to the bot.
     * @param contextVariables A map of variables to pass to the bot with this message.
     * @return A BotApiResponse object containing the conversationId and the bot's response message.
     */
    @AuraEnabled(cacheable=false) // Must be false for DML/external calls
    public static BotApiResponse sendMessageToBot(String botId, String conversationId, String message, Map<String, Object> contextVariables) {
        return sendBotMessage(botId, conversationId, message, contextVariables);
    }

    /**
     * Helper method to send a message to the Einstein Bot API.
     * This method handles both starting new conversations and continuing existing ones.
     * It parses the bot's response to extract the conversation ID and message text.
     *
     * @param botId The ID of the Einstein Bot.
     * @param conversationId The current conversation ID (null if starting new).
     * @param message The message to send.
     * @param contextVariables Additional context variables for the bot.
     * @return A BotApiResponse object with the bot's response.
     */
    private static BotApiResponse sendBotMessage(String botId, String conversationId, String message, Map<String, Object> contextVariables) {
        String endpoint = URL.getOrgDomainUrl().toExternalForm() + '/services/data/v58.0/connect/bots/' + botId + '/conversations'; // Use latest API version available in your org

        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId()); // Use current user's session ID for authentication

        Map<String, Object> requestBody = new Map<String, Object>();
        requestBody.put('message', message);

        if (String.isNotBlank(conversationId)) {
            requestBody.put('conversationId', conversationId);
        }

        if (contextVariables != null && !contextVariables.isEmpty()) {
            // Variables must be inside a 'variables' key in the request body
            requestBody.put('variables', contextVariables);
        }

        req.setBody(JSON.serialize(requestBody));

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

            String newConversationId = (String) responseMap.get('conversationId');
            String botMessageText = 'No text response from bot.'; // Default

            List<Object> botMessages = (List<Object>) responseMap.get('botMessages');
            if (botMessages != null && !botMessages.isEmpty()) {
                // Assuming we're interested in the text content of the first message
                Map<String, Object> firstMessage = (Map<String, Object>) botMessages[0];
                Map<String, Object> messageContent = (Map<String, Object>) firstMessage.get('messageContent');
                if (messageContent != null && messageContent.containsKey('text')) {
                    botMessageText = (String) messageContent.get('text');
                }
                // You can add logic here to parse other types of messageContent
                // (e.g., choices, images, links) if your bot uses them.
            }

            return new BotApiResponse(newConversationId, botMessageText);
        } else {
            // Log the error and throw an exception
            System.debug('Einstein Bot API Error - Status Code: ' + res.getStatusCode() + ', Response Body: ' + res.getBody());
            throw new AuraHandledException('Error communicating with Einstein Bot. Status: ' + res.getStatusCode() + ' - ' + res.getStatus() + '. Body: ' + res.getBody());
        }
    }
}