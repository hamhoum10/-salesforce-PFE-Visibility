import { LightningElement, wire, track } from 'lwc';
import getCasesWithoutAccount from '@salesforce/apex/CaseManagerController.getCasesWithoutAccount';
import linkAccountToCase from '@salesforce/apex/CaseManagerController.linkAccountToCase';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

const COLUMNS = [
    { label: 'Case Number', fieldName: 'CaseNumber', type: 'text' },
    { label: 'Subject', fieldName: 'Subject', type: 'text' },
    { label: 'Status', fieldName: 'Status', type: 'text' },
    { label: 'Priority', fieldName: 'Priority', type: 'text' },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Link Account', name: 'link_account' }
            ],
            menuAlignment: 'right'
        }
    }
];

export default class UnlinkedCasesManager extends LightningElement {
    @track cases = [];
    @track error;
    @track isLoading = false;
    columns = COLUMNS;

    @track showLinkAccountModal = false;
    @track selectedCaseId = null;
    @track selectedCaseNumber = '';
    @track selectedAccountId = null;
    @track isSaving = false;

    // A variable to hold the wired service result for refreshApex
    wiredCasesResult;

    @wire(getCasesWithoutAccount)
    wiredCases(result) {
        this.wiredCasesResult = result; // Store the wired result
        this.isLoading = true;
        if (result.data) {
            this.cases = result.data;
            this.error = undefined;
            this.isLoading = false;
        } else if (result.error) {
            this.error = 'Error retrieving cases: ' + this.reduceErrors(result.error).join(', ');
            this.cases = undefined;
            this.isLoading = false;
            this.showToast('Error', this.error, 'error');
        }
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'link_account') {
            this.selectedCaseId = row.Id;
            this.selectedCaseNumber = row.CaseNumber;
            this.selectedAccountId = null; // Reset selected account
            this.showLinkAccountModal = true;
        }
    }

    closeLinkAccountModal() {
        this.showLinkAccountModal = false;
        this.selectedCaseId = null;
        this.selectedCaseNumber = '';
        this.selectedAccountId = null;
    }

    handleAccountSelection(event) {
        this.selectedAccountId = event.detail.value;
    }

    async handleLinkAccountSave() {
        if (!this.selectedCaseId || !this.selectedAccountId) {
            this.showToast('Error', 'Please select an account to link.', 'error');
            return;
        }

        this.isSaving = true;
        try {
            const success = await linkAccountToCase({
                caseId: this.selectedCaseId,
                accountId: this.selectedAccountId[0] // lightning-input-field for lookup returns an array
            });

            if (success) {
                this.showToast('Success', 'Account linked to case successfully!', 'success');
                this.closeLinkAccountModal();
                // Refresh the wired data to update the list
                await refreshApex(this.wiredCasesResult);
            } else {
                this.showToast('Error', 'Failed to link account to case.', 'error');
            }
        } catch (error) {
            this.error = 'Error linking account: ' + this.reduceErrors(error).join(', ');
            this.showToast('Error', this.error, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(event);
    }

    // Helper function to reduce error messages from AuraHandledException
    reduceErrors(errors) {
        if (!Array.isArray(errors)) {
            errors = [errors];
        }

        return (
            errors
                // Remove null/undefined items
                .filter((error) => !!error)
                // Extract an error message
                .map((error) => {
                    // UI API read errors
                    if (Array.isArray(error.body)) {
                        return error.body.map((e) => e.message);
                    }
                    // Page level errors
                    else if (
                        typeof error.body === 'object' &&
                        error.body.pageErrors &&
                        error.body.pageErrors.length
                    ) {
                        return error.body.pageErrors.map((e) => e.message);
                    }
                    // Field level errors
                    else if (
                        typeof error.body === 'object' &&
                        error.body.fieldErrors &&
                        Object.keys(error.body.fieldErrors).length
                    ) {
                        const fieldErrors = [];
                        Object.values(error.body.fieldErrors).forEach((errorMessage) => {
                            fieldErrors.push(errorMessage);
                        });
                        return fieldErrors;
                    }
                    // AuraHandledException
                    else if (typeof error.body === 'object' && error.body.message) {
                        return error.body.message;
                    }
                    // Unknown error shape
                    return error.message || error;
                })
                // Flatten array of messages
                .flat()
        );
    }
}