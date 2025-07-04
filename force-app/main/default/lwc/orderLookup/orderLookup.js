import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';

// Import Apex methods
import getOrdersAndDetailsByEmail from '@salesforce/apex/omri.getOrdersAndDetailsByEmail';
import refundStatus from '@salesforce/apex/omri.refundStatus';
import reorderOrder from '@salesforce/apex/omri.reorderOrder';

export default class OrderManagement extends LightningElement {
    @track customerEmail = '';
    @track orders = []; // Original detailed order data from Apex
    @track pagedOrders = []; // Data for the current page in lightning-datatable
    @track isLoading = false;
    @track ordersFound = false;
    @track noOrdersFound = false;
    @track hasError = false;
    @track errorMessage = '';

    // Pagination properties
    @track currentPage = 1;
    @track itemsPerPage = 5;
    @track totalRecords = 0;
    @track totalPages = 1;

    // Sorting properties
    @track sortBy;
    @track sortDirection;

    columns = [
        { label: 'Order ID', fieldName: 'orderId', type: 'text', sortable: true },
        { label: 'Status', fieldName: 'orderStatus', type: 'text', sortable: true },
        { label: 'Effective Date', fieldName: 'effectiveDate', type: 'date', sortable: true },
        { label: 'Refund Status', fieldName: 'refundStatus', type: 'text', sortable: true },
        { label: 'Account Name', fieldName: 'accountName', type: 'text', sortable: true },
        {
            type: 'action',
            typeAttributes: {
                rowActions: this.getRowActions,
                menuAlignment: 'auto'
            }
        }
    ];

    getRowActions(row, doneCallback) {
        const actions = [
            { label: 'Update Refund Status', name: 'update_refund_status', iconName: 'utility:refresh' },
            { label: 'Reorder', name: 'reorder_order', iconName: 'utility:recycle' }
        ];
        doneCallback(actions);
    }

    handleEmailChange(event) {
        this.customerEmail = event.target.value;
    }

    async handleFetchOrders() {
        if (!this.customerEmail) {
            this.showToast('Error', 'Please enter a customer email.', 'error');
            return;
        }

        this.isLoading = true;
        this.ordersFound = false;
        this.noOrdersFound = false;
        this.hasError = false;
        this.errorMessage = '';
        this.orders = []; // Clear previous full data
        this.pagedOrders = []; // Clear previous table data
        this.currentPage = 1; // Reset to first page on new fetch

        try {
            const result = await getOrdersAndDetailsByEmail({ email: this.customerEmail });
            if (result && result.length > 0) {
                this.orders = result.map(order => ({
                    orderId: order.orderId,
                    orderStatus: order.orderDetails.Status,
                    effectiveDate: order.orderDetails.EffectiveDate,
                    refundStatus: order.orderDetails.Refund_Status__c || 'NoRefund',
                    accountName: order.accountDetails.Name,
                }));
                this.totalRecords = this.orders.length;
                this.totalPages = Math.ceil(this.totalRecords / this.itemsPerPage);
                this.ordersFound = true;
                this.updatePagedOrders(); // Populate table with first page
            } else {
                this.noOrdersFound = true;
                this.totalRecords = 0;
                this.totalPages = 1;
            }
        } catch (error) {
            this.hasError = true;
            this.errorMessage = error.body ? error.body.message : error.message;
            console.error('Error fetching orders:', error);
            this.showToast('Error', 'Failed to fetch orders: ' + this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    updatePagedOrders() {
        const start = (this.currentPage - 1) * this.itemsPerPage;
        const end = start + this.itemsPerPage;
        let slicedData = [...this.orders]; // Create a shallow copy for sorting/slicing

        // Apply sorting if sortBy is set
        if (this.sortBy) {
            slicedData.sort((a, b) => {
                let valA = a[this.sortBy] || '';
                let valB = b[this.sortBy] || '';

                // Handle date comparison
                if (this.columns.find(col => col.fieldName === this.sortBy && col.type === 'date')) {
                    valA = new Date(valA);
                    valB = new Date(valB);
                }

                if (valA > valB) {
                    return this.sortDirection === 'asc' ? 1 : -1;
                } else if (valA < valB) {
                    return this.sortDirection === 'asc' ? -1 : 1;
                }
                return 0;
            });
        }
        
        this.pagedOrders = slicedData.slice(start, end);
    }

    handleSort(event) {
        this.sortBy = event.detail.fieldName;
        this.sortDirection = event.detail.sortDirection;
        this.updatePagedOrders();
    }

    handlePreviousPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.updatePagedOrders();
        }
    }

    handleNextPage() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
            this.updatePagedOrders();
        }
    }

    handleItemsPerPageChange(event) {
        this.itemsPerPage = parseInt(event.target.value, 10);
        this.currentPage = 1; // Reset to first page
        this.totalPages = Math.ceil(this.totalRecords / this.itemsPerPage);
        this.updatePagedOrders();
    }

    get isFirstPage() {
        return this.currentPage === 1;
    }

    get isLastPage() {
        return this.currentPage === this.totalPages || this.totalPages === 0;
    }

    async handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        const orderId = row.orderId;

        switch (action.name) {
            case 'update_refund_status':
                this.handleUpdateRefundStatus(orderId, row.refundStatus);
                break;
            case 'reorder_order':
                this.handleReorder(orderId);
                break;
            default:
                break;
        }
    }

    async handleUpdateRefundStatus(orderId, currentRefundStatus) {
        const newStatus = prompt(`Enter new Refund Status (NoRefund, Refund, HalfRefund, Exchange) for Order ID: ${orderId}. Current: ${currentRefundStatus}`);

        if (newStatus && ['NoRefund', 'Refund', 'HalfRefund', 'Exchange'].includes(newStatus)) {
            this.isLoading = true;
            try {
                const success = await refundStatus({ externalOrderId: orderId, refundStatus: newStatus });
                if (success) {
                    this.showToast('Success', 'Refund Status updated successfully.', 'success');
                    // Refetch orders to update the table display
                    this.handleFetchOrders();
                } else {
                    this.showToast('Error', 'Failed to update Refund Status.', 'error');
                }
            } catch (error) {
                console.error('Error updating refund status:', error);
                this.showToast('Error', 'Failed to update refund status: ' + (error.body ? error.body.message : error.message), 'error');
            } finally {
                this.isLoading = false;
            }
        } else if (newStatus !== null) {
            this.showToast('Warning', 'Invalid refund status entered. Please choose from: NoRefund, Refund, HalfRefund, Exchange.', 'warning');
        }
    }

    async handleReorder(originalOrderId) {
        this.isLoading = true;
        try {
            const newOrderId = await reorderOrder({ externalOrderId: originalOrderId });
            if (newOrderId) {
                this.showToast('Success', `Order reordered successfully. New Order ID: ${newOrderId}`, 'success');
                this.handleFetchOrders();
            } else {
                this.showToast('Error', 'Failed to reorder the order.', 'error');
            }
        } catch (error) {
            console.error('Error reordering order:', error);
            this.showToast('Error', 'Failed to reorder order: ' + (error.body ? error.body.message : error.message), 'error');
        } finally {
            this.isLoading = false;
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
}