// linkedCasesTable.js
import { LightningElement, wire, track, api } from 'lwc';
import getCasesWithAccount from '@salesforce/apex/CaseManagerController.getCasesWithAccount';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Define columns for the lightning-datatable
const COLUMNS = [
    { label: 'Case Number', fieldName: 'CaseNumber', type: 'text' },
    {
        label: 'Account Name',
        fieldName: 'accountName', // This will come from the getter
        type: 'button',
        typeAttributes: { label: { fieldName: 'accountName' }, name: 'view_account_details', variant: 'base' }
    },
    { label: 'Subject', fieldName: 'Subject', type: 'text' },
    { label: 'Status', fieldName: 'Status', type: 'text' },
    { label: 'Priority', fieldName: 'Priority', type: 'text' },
];

export default class LinkedCasesTable extends LightningElement {
    @track cases = []; // Reactive property to store cases data
    @track error;    // Reactive property to store any error messages
    columns = COLUMNS; // Assign the defined columns to the datatable

    // Getter to check if no linked cases are found. This avoids complex expressions in HTML.
    get noLinkedCasesFound() {
        return this.cases.length === 0;
    }

    // Wire method to call the Apex method getCasesWithAccount
    @wire(getCasesWithAccount)
    wiredCases({ error, data }) {
        if (data) {
            this.cases = data.map(caseRec => {
                // Flatten Account.Name into a top-level property for datatable
                return {
                    ...caseRec,
                    accountName: caseRec.Account ? caseRec.Account.Name : ''
                };
            });
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
        return getCasesWithAccount()
            .then(result => {
                this.cases = result.map(caseRec => {
                    return {
                        ...caseRec,
                        accountName: caseRec.Account ? caseRec.Account.Name : ''
                    };
                });
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

        // If the action is 'view_account_details', dispatch a custom event
        if (actionName === 'view_account_details') {
            this.dispatchEvent(new CustomEvent('viewaccountdetail', {
                detail: { accountId: row.AccountId } // Pass the Account Id in the event detail
            }));
        }
    }
}