// AccountSearchAndLink.js
import { LightningElement, api, track } from 'lwc';
import searchAccounts from '@salesforce/apex/CaseManagerController.searchAccounts';
import linkAccountToCase from '@salesforce/apex/CaseManagerController.linkAccountToCase';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class AccountSearchAndLink extends NavigationMixin(LightningElement) {
    @api caseId;
    @api recordId;

    @track searchName = '';
    @track searchEmail = '';
    @track searchPhone = '';
    @track accounts = [];
    @track selectedAccountId = '';
    @track error;
    @track isLoading = false;
    @track successMessage = '';

    // Getter to format accounts for the lightning-radio-group options
    get accountOptions() {
        return this.accounts.map(account => {
            let label = account.Name;
            if (account.PersonEmail) {
                label += ` (${account.PersonEmail})`;
            } else if (account.Phone) {
                label += ` (${account.Phone})`;
            }
            return { label: label, value: String(account.Id) }; // Ensure value is a string
        });
    }

    // Getter to determine if no accounts were found after a search with a term
    get noAccountsFoundWithSearchTerm() {
        return this.accounts.length === 0 && (this.searchName || this.searchEmail || this.searchPhone) && !this.isLoading;
    }

    // NEW: Getter to control the disabled state of the "Link Selected Account" button
    // The button should be disabled if no account is selected (selectedAccountId is falsy).
    get isLinkButtonDisabled() {
        return !this.selectedAccountId;
    }

    // Handles changes to the name search input field
    handleNameChange(event) {
        this.searchName = event.target.value;
    }

    // Handles changes to the email search input field
    handleEmailChange(event) {
        this.searchEmail = event.target.value;
    }

    // Handles changes to the phone search input field
    handlePhoneChange(event) {
        this.searchPhone = event.target.value;
    }

    // NEW: Clears the search fields and results
    clearSearch() {
        this.searchName = '';
        this.searchEmail = '';
        this.searchPhone = '';
        this.accounts = [];
        this.selectedAccountId = '';
        this.error = undefined;
        this.successMessage = '';
    }

    // Initiates the account search based on the search fields
    searchAccounts() {
        if (!this.searchName && !this.searchEmail && !this.searchPhone) {
            this.accounts = []; // Clear accounts if no search fields are filled
            this.selectedAccountId = ''; // Reset selection
            this.error = 'Please enter at least one search field.'; // Set error message
            this.successMessage = '';
            return;
        }
        this.isLoading = true;
        this.error = undefined;
        this.successMessage = '';
        searchAccounts({ name: this.searchName, email: this.searchEmail, phone: this.searchPhone })
            .then(result => {
                this.accounts = result; // Assign search results to accounts
                this.selectedAccountId = ''; // Reset selection on new search
                // Set error message if no accounts are found
                if (this.accounts.length === 0) {
                    this.error = 'No accounts found matching your search.';
                } else {
                    this.error = undefined; // Clear error if accounts are found
                }
            })
            .catch(error => {
                // Handle errors during account search
                this.error = error.body ? error.body.message : error.message;
                this.accounts = []; // Clear accounts on error
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error searching accounts',
                        message: this.error,
                        variant: 'error',
                    }),
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Handles selection of an account from the radio group
    handleAccountSelection(event) {
        this.selectedAccountId = event.detail.value;
        // Debug log to verify selection
         console.log('Selected Account Id:', this.selectedAccountId);
    }

    // Links the selected account to the case
    linkAccount() {
        // Use recordId if caseId is not set
        const caseIdToUse = this.caseId || this.recordId;
        // Debug log
        // console.log('Linking: caseIdToUse =', caseIdToUse, ', selectedAccountId =', this.selectedAccountId);

        if (!caseIdToUse && !this.selectedAccountId) {
            this.error = 'Please select an account and make sure this component is used on a Case record page.';
            this.successMessage = '';
            return;
        }
        if (!caseIdToUse) {
            this.error = 'No Case Id found. Make sure this component is used on a Case record page.';
            this.successMessage = '';
            return;
        }
        if (!this.selectedAccountId) {
            this.error = 'Please select an account to link.';
            this.successMessage = '';
            return;
        }
        this.isLoading = true;
        this.error = undefined;
        linkAccountToCase({ caseId: caseIdToUse, accountId: this.selectedAccountId })
            .then(result => {
                if (result) {
                    this.successMessage = 'Account linked to case successfully!';
                    this.error = undefined;
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Success',
                            message: 'Account linked to case successfully!',
                            variant: 'success',
                        }),
                    );
                    // Refetch data after update
                    this.searchAccounts();
                    // Dispatch a custom event to notify the parent component (e.g., to close modal and refresh data)
                    this.dispatchEvent(new CustomEvent('accountlinked'));
                    // Navigate to the Case record page to refresh the view
                    this[NavigationMixin.Navigate]({
                        type: 'standard__recordPage',
                        attributes: {
                            recordId: caseIdToUse,
                            objectApiName: 'Case',
                            actionName: 'view'
                        }
                    }, true);
                } else {
                    this.error = 'Failed to link account to case.';
                    this.successMessage = '';
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Error',
                            message: this.error,
                            variant: 'error',
                        }),
                    );
                }
            })
            .catch(error => {
                this.error = error.body ? error.body.message : error.message;
                this.successMessage = '';
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error linking account',
                        message: this.error,
                        variant: 'error',
                    }),
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
}