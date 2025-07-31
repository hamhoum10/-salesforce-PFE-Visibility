import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ChatLwc extends LightningElement {
    @track currentMessage = '';
    @track chatMessages = []; // Stores objects like { id: ..., text: ..., type: 'user-message' | 'agent-message' }
    @track flowStarted = false; // Controls when to render/start the flow
    @track isSending = false; // To disable send button during processing
    @track isThinking = false; // To show "Agent is typing..."

    flowApiName = 'testmail'; // **IMPORTANT: Replace with your actual Flow API Name**

    // Variables to pass to the flow (input)
    flowInputVariables = [];

    connectedCallback() {
        // You might want to load initial chat history here if applicable
    }

    handleMessageChange(event) {
        this.currentMessage = event.target.value;
    }

    handleKeyUp(event) {
        if (event.keyCode === 13) { // Enter key
            this.handleSendMessage();
        }
    }

    handleSendMessage() {
        if (!this.currentMessage.trim()) {
            return; // Don't send empty messages
        }

        const userMessage = this.currentMessage.trim();

        // Add user message to chat history
        this.chatMessages.push({
            id: Date.now() + '-user',
            text: userMessage,
            type: 'user-message'
        });

        this.isSending = true;
        this.isThinking = true; // Show typing indicator

        // Prepare input for the Flow
        this.flowInputVariables = [
            {
                name: 'input', // Matches the Flow's input variable API name
                type: 'String',
                value: userMessage
            }
        ];

        // Trigger the Flow
        this.flowStarted = true;
        this.currentMessage = ''; // Clear the input field
    }

    handleFlowStatusChange(event) {
        if (event.detail.status === 'FINISHED') {
            this.flowStarted = false; // Hide the flow component

            const outputVariables = event.detail.outputVariables;
            let agentResponse = 'No response from agent.';

            // Find the output variable from the Flow
            for (let i = 0; i < outputVariables.length; i++) {
                const outputVar = outputVariables[i];
                if (outputVar.name === 'output') { // Matches the Flow's output variable API name
                    agentResponse = outputVar.value;
                    break;
                }
            }

            // Add agent response to chat history
            this.chatMessages.push({
                id: Date.now() + '-agent',
                text: agentResponse,
                type: 'agent-message'
            });

            this.isSending = false;
            this.isThinking = false; // Hide typing indicator
            this.scrollToBottom(); // Scroll to the latest message
        } else if (event.detail.status === 'ERROR') {
            this.flowStarted = false;
            this.isSending = false;
            this.isThinking = false;
            this.showToast('Error', 'Flow encountered an error: ' + event.detail.errorMessage, 'error');
            // You might want to log the full error or add a generic error message to chat
            this.chatMessages.push({
                id: Date.now() + '-error',
                text: 'Error contacting agent. Please try again.',
                type: 'agent-message error-message'
            });
        }
        // Other statuses like 'STARTED', 'PAUSED' are less relevant for Auto-Launched Flows
    }

    scrollToBottom() {
        const chatHistory = this.template.querySelector('.chat-history');
        if (chatHistory) {
            chatHistory.scrollTop = chatHistory.scrollHeight;
        }
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}