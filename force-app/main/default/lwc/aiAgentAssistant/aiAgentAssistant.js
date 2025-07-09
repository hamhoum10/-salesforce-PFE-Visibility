import { LightningElement, api, track } from 'lwc';
import sendMessageToBot from '@salesforce/apex/EinsteinBotService.sendMessageToBot';
import startNewBotConversation from '@salesforce/apex/EinsteinBotService.startNewBotConversation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AiAgentAssistant extends LightningElement {
    @api recordId;        // ID of the current record (e.g., Case ID, Order ID)
    @api objectApiName;   // API Name of the current object (e.g., 'Case', 'Order__c')

    @track chatMessages = []; // Stores messages to display in the chat window
    @track currentConversationId = null;
    @track isLoading = false;
    @track userInput = '';
    @track isBotAvailable = false; // Flag to indicate if bot is configured correctly

    // !!! IMPORTANT: REPLACE WITH YOUR ACTUAL EINSTEIN BOT ID !!!
    // This MUST be the 18-character ID found in Salesforce Setup -> Einstein Bots -> Select your bot -> Details page.
    // It typically starts with '0K0'.
    botId = '0XxgK000000KnXdSAK'; // Using your provided ID, but adjusted to standard '0K0' prefix.
                                  // PLEASE VERIFY THIS ID FROM YOUR ORG.

    connectedCallback() {
        console.log('LWC: Connected callback. Bot ID set in LWC:', this.botId);

        // Standard Einstein Bot IDs start with '0K0'.
        if (this.botId && this.botId.startsWith('0Xx') && this.botId.length === 18) {
            this.isBotAvailable = true;
            this.startBotConversationWithContext();
        } else {
            this.isBotAvailable = false;
            let errorMessage = 'Invalid Einstein Bot ID. It must be an 18-character ID starting with "0K0".';
            if (this.botId === '0XxgK000000KnXdSAK') {
                errorMessage = 'The provided Bot ID ("0XxgK...") is not in the standard Einstein Bot format ("0K0..."). Please verify the ID from Salesforce Setup.';
            } else if (!this.botId) {
                errorMessage = 'Einstein Bot ID is not configured. Please set the `botId` variable in `aiAgentAssistant.js`.';
            }
            this.showToast('Error', errorMessage, 'error');
            console.error('LWC Error: Bot ID validation failed.', this.botId);
        }
    }

    async startBotConversationWithContext() {
        if (!this.isBotAvailable) return;

        this.isLoading = true;
        this.chatMessages = []; // Clear previous messages
        this.currentConversationId = null; // Ensure new conversation

        this.addMessage('Bot', 'Starting conversation...', 'bot');

        // Prepare context variables for the bot
        // These variables are passed to the bot to provide context about the current record.
        // Your bot's dialogs should be configured to receive and use these variables.
        const contextVariables = {
            CurrentRecordId: this.recordId || 'N/A', // Pass the current record ID
            CurrentObjectName: this.objectApiName || 'N/A', // Pass the object API name
            // Add any other relevant data you want to send to your bot
            // Example:
            // CaseSubject: 'Inquiry about X',
            // CustomerEmail: 'customer@example.com'
        };

        try {
            const response = await startNewBotConversation({
                botId: this.botId,
                initialMessage: 'Hello, I need assistance with ',
                contextVariables: contextVariables
            });
            this.currentConversationId = response.conversationId;
            this.updateLastBotMessage(response.messageText); // Update 'Starting conversation...'
        } catch (error) {
            console.error('LWC Error starting bot conversation:', error);
            this.updateLastBotMessage('Error starting bot conversation. Please try again.');
            this.showToast('Error', 'Could not start bot conversation: ' + this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleInputChange(event) {
        this.userInput = event.target.value;
    }

    handleEnterKey(event) {
        if (event.key === 'Enter') {
            this.handleSendMessage();
        }
    }

    async handleSendMessage() {
        if (!this.userInput.trim() || this.isLoading || !this.isBotAvailable) {
            return;
        }

        this.isLoading = true;
        const messageToSend = this.userInput;
        this.userInput = ''; // Clear input field

        this.addMessage('You', messageToSend, 'user');
        this.addMessage('Bot', 'Thinking...', 'bot'); // Placeholder for bot response

        // Context variables can be updated or passed again for subsequent messages if needed.
        const contextVariables = {
            CurrentRecordId: this.recordId || 'N/A',
            CurrentObjectName: this.objectApiName || 'N/A',
        };

        try {
            const response = await sendMessageToBot({
                botId: this.botId,
                conversationId: this.currentConversationId,
                message: messageToSend,
                contextVariables: contextVariables
            });
            this.currentConversationId = response.conversationId; // Update conversation ID in case it changed
            this.updateLastBotMessage(response.messageText); // Update 'Thinking...' with actual response
        } catch (error) {
            console.error('LWC Error sending message to bot:', error);
            this.updateLastBotMessage('Error talking to bot. Please try again.');
            this.showToast('Error', 'Could not send message to bot: ' + this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Helper to add a message to the chat display
    addMessage(sender, text, type) {
        this.chatMessages = [...this.chatMessages, {
            id: new Date().getTime() + '-' + Math.random(), // Unique ID
            sender: sender,
            text: text,
            cssClass: type === 'user' ? 'message-bubble user-message slds-text-align_right' : 'message-bubble bot-message slds-text-align_left'
        }];
        // Defer scrolling to ensure DOM updates have occurred
        requestAnimationFrame(() => {
            this.scrollChatToBottom();
        });
    }

    // Helper to update the last bot message (e.g., from "Thinking..." to actual response)
    updateLastBotMessage(newText) {
        if (this.chatMessages.length > 0) {
            const lastMessage = this.chatMessages[this.chatMessages.length - 1];
            if (lastMessage.sender === 'Bot' && (lastMessage.text === 'Thinking...' || lastMessage.text === 'Starting conversation...')) {
                lastMessage.text = newText;
                // Re-assign array to trigger reactivity
                this.chatMessages = [...this.chatMessages];
            } else {
                this.addMessage('Bot', newText, 'bot'); // Add new if last wasn't a placeholder
            }
        } else {
            this.addMessage('Bot', newText, 'bot'); // Add if no messages yet
        }
        // Defer scrolling to ensure DOM updates have occurred
        requestAnimationFrame(() => {
            this.scrollChatToBottom();
        });
    }

    // Scrolls the chat window to the bottom
    scrollChatToBottom() {
        const chatWindow = this.template.querySelector('.chat-window');
        if (chatWindow) { // Always check if the element exists
            chatWindow.scrollTop = chatWindow.scrollHeight;
        } else {
            console.warn('LWC Warning: Chat window element not found for scrolling.');
        }
    }

    // Helper to show a toast message
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'sticky' // Keep toast visible longer for errors
        });
        this.dispatchEvent(event);
    }

    // Helper to extract error message from various error structures
    getErrorMessage(error) {
        if (error.body && error.body.message) {
            return error.body.message;
        } else if (error.message) {
            return error.message;
        }
        // For AuraHandledException, the message is directly in error.body.message
        if (typeof error.body === 'string') {
             try {
                const errorBodyParsed = JSON.parse(error.body);
                return errorBodyParsed.message || 'Unknown error from Apex body';
             } catch (e) {
                return error.body; // Return raw string if not JSON
             }
        }
        return JSON.stringify(error); // Fallback for unexpected error formats
    }
}