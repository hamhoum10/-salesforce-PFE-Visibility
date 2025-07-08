import { LightningElement, track } from 'lwc';

export default class CaseManagementApp extends LightningElement {
    @track showUnlinked = true;
    @track showLinked = false;
    @track selectedCaseIdForLinking;
    @track isAccountSearchModalOpen = false;
    @track selectedAccountIdForDetails;
    @track isAccountDetailsModalOpen = false;
    @track selectedOrderItems;
    @track isOrderItemsModalOpen = false;

    get unlinkedVariant() {
        return this.showUnlinked ? 'brand' : 'neutral';
    }

    get linkedVariant() {
        return this.showLinked ? 'brand' : 'neutral';
    }

    showUnlinkedCases() {
        this.showUnlinked = true;
        this.showLinked = false;
    }

    showLinkedCases() {
        this.showUnlinked = false;
        this.showLinked = true;
    }

    handleLinkCase(event) {
        this.selectedCaseIdForLinking = event.detail.caseId;
        this.isAccountSearchModalOpen = true;
    }

    closeAccountSearchModal() {
        this.isAccountSearchModalOpen = false;
        this.selectedCaseIdForLinking = null;
        // Refresh unlinked cases table after linking
        const unlinkedTable = this.template.querySelector('c-unlinked-cases-table');
        if (unlinkedTable && unlinkedTable.refreshCases) {
             unlinkedTable.refreshCases();
        }
    }

    handleAccountLinked() {
        this.closeAccountSearchModal();
        // Refresh both tables after an account is linked
        const unlinkedTable = this.template.querySelector('c-unlinked-cases-table');
        if (unlinkedTable && unlinkedTable.refreshCases) {
             unlinkedTable.refreshCases();
        }
        const linkedTable = this.template.querySelector('c-linked-cases-table');
        if (linkedTable && linkedTable.refreshCases) {
             linkedTable.refreshCases();
        }
    }

    handleViewAccountDetail(event) {
        this.selectedAccountIdForDetails = event.detail.accountId;
        this.isAccountDetailsModalOpen = true;
    }

    closeAccountDetailsModal() {
        this.isAccountDetailsModalOpen = false;
        this.selectedAccountIdForDetails = null;
    }

    handleViewOrderItems(event) {
        this.selectedOrderItems = event.detail.orderItems;
        this.isOrderItemsModalOpen = true;
    }

    closeOrderItemsModal() {
        this.isOrderItemsModalOpen = false;
        this.selectedOrderItems = null;
    }
}