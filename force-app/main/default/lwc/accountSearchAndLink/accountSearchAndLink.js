// AccountSearchAndLink.js
import { LightningElement, api, track } from 'lwc';
import searchAccounts from '@salesforce/apex/CaseManagerController.searchAccounts';
import linkAccountToCase from '@salesforce/apex/CaseManagerController.linkAccountToCase';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AccountSearchAndLink extends LightningElement {
    @api caseId; // Public property to receive the Case ID
    @track searchTerm = ''; // Reactive property for the search input
    @track accounts = []; // Reactive property to store search results
    @track selectedAccountId = ''; // Reactive property for the selected account ID from radio group
    @track error; // Reactive property to store any error messages

    // Getter to format accounts for the lightning-radio-group options
    get accountOptions() {
        return this.accounts.map(account => {
            let label = account.Name;
            if (account.PersonEmail) {
                label += ` (${account.PersonEmail})`;
            } else if (account.Phone) {
                label += ` (${account.Phone})`;
            }
            return { label: label, value: account.Id };
        });
    }

    // Getter to determine if no accounts were found after a search with a term
    get noAccountsFoundWithSearchTerm() {
        return this.accounts.length === 0 && this.searchTerm;
    }

    // NEW: Getter to control the disabled state of the "Link Selected Account" button
    // The button should be disabled if no account is selected (selectedAccountId is falsy).
    get isLinkButtonDisabled() {
        return !this.selectedAccountId;
    }

    // Handles changes to the search term input field
    handleSearchTermChange(event) {
        this.searchTerm = event.target.value;
    }

    // Initiates the account search based on the searchTerm
    searchAccounts() {
        if (!this.searchTerm) {
            this.accounts = []; // Clear accounts if search term is empty
            this.selectedAccountId = ''; // Reset selection
            this.error = 'Please enter a search term.'; // Set error message
            return;
        }

        this.error = undefined; // Clear any previous errors
        searchAccounts({ searchTerm: this.searchTerm })
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
            });
    }

    // Handles selection of an account from the radio group
    handleAccountSelection(event) {
        this.selectedAccountId = event.detail.value;
    }

    // Links the selected account to the case
    linkAccount() {
        if (!this.caseId || !this.selectedAccountId) {
            this.error = 'Please select an account to link.';
            return;
        }

        linkAccountToCase({ caseId: this.caseId, accountId: this.selectedAccountId })
            .then(result => {
                if (result) {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Success',
                            message: 'Account linked to case successfully!',
                            variant: 'success',
                        }),
                    );
                    // Dispatch a custom event to notify the parent component (e.g., to close modal and refresh data)
                    this.dispatchEvent(new CustomEvent('accountlinked'));
                } else {
                    this.error = 'Failed to link account to case.';
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
                // Handle errors during account linking
                this.error = error.body ? error.body.message : error.message;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error linking account',
                        message: this.error,
                        variant: 'error',
                    }),
                );
            });
    }
}