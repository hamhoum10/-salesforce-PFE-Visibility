// unlinkedCasesManager.js
import { LightningElement, wire, track, api } from 'lwc';
import getCasesWithoutAccount from '@salesforce/apex/CaseManagerController.getCasesWithoutAccount';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Define actions for the row in the datatable
const ACTIONS = [
    { label: 'Link Account', name: 'link_account' },
];

// Define columns for the lightning-datatable
const COLUMNS = [
    { label: 'Case Number', fieldName: 'CaseNumber', type: 'text' },
    { label: 'Subject', fieldName: 'Subject', type: 'text' },
    { label: 'Status', fieldName: 'Status', type: 'text' },
    { label: 'Priority', fieldName: 'Priority', type: 'text' },
    {
        type: 'action',
        typeAttributes: { rowActions: ACTIONS },
    },
];

// Export the component class
export default class UnlinkedCasesManager extends LightningElement {
    @track cases = []; // Reactive property to store cases data
    @track error;    // Reactive property to store any error messages
    columns = COLUMNS; // Assign the defined columns to the datatable

    // Getter to check if no cases are found. This avoids complex expressions in HTML.
    get noCasesFound() {
        return this.cases.length === 0;
    }

    // Wire method to call the Apex method getCasesWithoutAccount
    @wire(getCasesWithoutAccount)
    wiredCases({ error, data }) {
        if (data) {
            this.cases = data;      // Assign data to cases property
            this.error = undefined; // Clear any previous errors
        } else if (error) {
            // Handle errors: extract message and set error property
            this.error = error.body ? error.body.message : error.message;
            this.cases = []; // Clear cases on error
            // Dispatch a toast event to show the error to the user
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error loading cases',
                    message: this.error,
                    variant: 'error',
                }),
            );
        }
    }

    // Public method to refresh the cases data
    @api
    refreshCases() {
        // Call the Apex method again to get updated data
        return getCasesWithoutAccount()
            .then(result => {
                this.cases = result;      // Update cases with new data
                this.error = undefined; // Clear errors
            })
            .catch(error => {
                // Handle errors during refresh
                this.error = error.body ? error.body.message : error.message;
                this.cases = []; // Clear cases on error
                // Dispatch a toast event for refresh errors
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error refreshing cases',
                        message: this.error,
                        variant: 'error',
                    }),
                );
            });
    }

    // Handler for row actions in the datatable
    handleRowAction(event) {
        const actionName = event.detail.action.name; // Get the name of the action performed
        const row = event.detail.row;               // Get the data of the row on which action was performed

        // If the action is 'link_account', dispatch a custom event
        if (actionName === 'link_account') {
            this.dispatchEvent(new CustomEvent('linkcase', {
                detail: { caseId: row.Id } // Pass the Case Id in the event detail
            }));
        }
    }
}