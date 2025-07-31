import { LightningElement, api, track } from 'lwc';
import updateExternalOrderItemQuantity from '@salesforce/apex/omri.updateExternalOrderItemQuantity';
import deleteExternalOrderItem from '@salesforce/apex/omri.deleteExternalOrderItem';

const ACTIONS = [
    // Removed 'Edit Quantity' action
    { label: 'Delete', name: 'delete' }
];

const COLUMNS = [
    { label: 'Product Name', fieldName: 'ProductName', type: 'text', sortable: true },
    { label: 'Quantity', fieldName: 'quantity', type: 'number', editable: true, sortable: true },
    { label: 'Unit Price', fieldName: 'unitPrice', type: 'currency', sortable: true },
    {
        type: 'action',
        typeAttributes: { rowActions: ACTIONS }
    }
    // Add more fields from OrderItemDetail and productDetails as needed
];

export default class OrderItemDetails extends LightningElement {
    @api orderItems = []; // Public property to receive order items
    columns = COLUMNS; // Columns for the datatable
    @track isLoading = false;
    @track draftValues = [];
    @track changedRows = {};

    @api sortBy = 'quantity';
    @api sortDirection = 'asc';

    // Process orderItems to flatten productDetails for display in the datatable
    get processedOrderItems() {
        let items = this.orderItems.map(item => ({
            ...item,
            // Assuming 'Name' is a field on Product2 within productDetails
            ProductName: item.productDetails ? item.productDetails.Name : 'N/A'
        }));
        // Sorting logic
        if (this.sortBy && this.sortDirection) {
            items = [...items].sort((a, b) => {
                let valA = a[this.sortBy];
                let valB = b[this.sortBy];
                if (valA === undefined || valA === null) valA = '';
                if (valB === undefined || valB === null) valB = '';
                if (valA < valB) return this.sortDirection === 'asc' ? -1 : 1;
                if (valA > valB) return this.sortDirection === 'asc' ? 1 : -1;
                return 0;
            });
        }
        return items;
    }

    // Getter to determine if there are no processed order items to display
    get noOrderItemsToDisplay() {
        return this.processedOrderItems.length === 0;
    }

    get showSaveCancel() {
        return this.draftValues.length > 0;
    }

    // Handle row actions (edit/delete)
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === 'delete') {
            this.deleteOrderItem(row);
        }
    }

    handleCellChange(event) {
        const drafts = event.detail.draftValues;
        drafts.forEach(draft => {
            this.changedRows[draft.orderItemId] = draft.quantity;
        });
        this.draftValues = drafts;
    }

    // Save changes by calling Apex for all changed rows
    async handleSave() {
        this.isLoading = true;
        try {
            const updatePromises = this.draftValues.map(draft =>
                updateExternalOrderItemQuantity({
                    externalOrderItemId: draft.orderItemId,
                    newQuantity: Number(draft.quantity)
                })
            );
            const results = await Promise.all(updatePromises);
            if (results.every(r => r)) {
                this.changedRows = {};
                this.draftValues = [];
                // Dispatch refresh and wait for parent to reload data
                this.dispatchEvent(new CustomEvent('refresh'));
            } else {
                alert('Failed to update one or more quantities.');
            }
        } catch (e) {
            alert('Error updating quantities.');
        }
        this.isLoading = false;
    }

    // Cancel edits and clear draft values
    handleCancel() {
        this.changedRows = {};
        this.draftValues = [];
    }

    // Call Apex to delete
    async deleteOrderItem(row) {
        if (confirm('Are you sure you want to delete this order item?')) {
            this.isLoading = true;
            try {
                const result = await deleteExternalOrderItem({ externalOrderItemId: row.orderItemId });
                if (result) {
                    // Clear drafts and changed rows after delete
                    this.changedRows = {};
                    this.draftValues = [];
                    this.dispatchEvent(new CustomEvent('refresh'));
                } else {
                    alert('Failed to delete order item.');
                }
            } catch (e) {
                alert('Error deleting order item.');
            }
            this.isLoading = false;
        }
    }

    handleSort(event) {
        this.sortBy = event.detail.fieldName;
        this.sortDirection = event.detail.sortDirection;
    }
}