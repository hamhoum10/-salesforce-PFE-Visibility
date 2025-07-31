import { LightningElement, api, track, wire } from 'lwc';
import getOrdersAndDetailsByEmail from '@salesforce/apex/omri.getOrdersAndDetailsByEmail';
import reorderOrder from '@salesforce/apex/omri.reorderOrder';
import getAccountById from '@salesforce/apex/omri.getAccountById';
import authenticate from '@salesforce/apex/omri.authenticate';
import deleteExternalOrder from '@salesforce/apex/omri.deleteExternalOrder';
import refundStatus from '@salesforce/apex/omri.refundStatus';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import ACCOUNT_ID_FIELD from '@salesforce/schema/Case.AccountId';

const ORDER_COLUMNS = [
    { label: 'Order ID', fieldName: 'orderId', type: 'button', typeAttributes: { label: { fieldName: 'orderId' }, name: 'view_order_items', variant: 'base' }, sortable: true },
    { label: 'Order Date', fieldName: 'EffectiveDate', type: 'date', sortable: true },
     { label: 'Total Amount', fieldName: 'TotalAmount', type: 'currency', sortable: true },
    { label: 'Refund Status', fieldName: 'Refund_Status__c', type: 'text' },
    {
        type: 'button',
        fixedWidth: 110,
        typeAttributes: {
            label: 'Reorder',
            name: 'reorder_order',
            title: 'Reorder',
            variant: 'brand',
            disabled: false
        }
    },
    {
        type: 'button',
        fixedWidth: 110,
        typeAttributes: {
            label: 'Delete',
            name: 'delete_order',
            title: 'Delete Order',
            variant: 'destructive',
            disabled: false
        }
    },
    {
        type: 'button',
        fixedWidth: 110,
        typeAttributes: {
            label: 'Refund',
            name: 'refund_order',
            title: 'Refund Order',
            variant: 'neutral',
            disabled: false
        }
    },
    {
        type: 'button',
        fixedWidth: 140,
        typeAttributes: {
            label: 'Partial Refund',
            name: 'partial_refund_order',
            title: 'Partial Refund Order',
            variant: 'neutral',
            disabled: false
        }
    }
];

export default class AccountDetailsAndOrders extends LightningElement {
    @api recordId; // Case ID from the record page

    @track accountDetails;
    @track accountDetailsError;
    @track orders = [];
    @track ordersError;
    orderColumns = ORDER_COLUMNS;
    @track accessToken;

    @track isModalOpen = false; // Controls visibility of the modal
    @track modalOrderItems = []; // Data for the OrderItemDetails component in the modal
    @track selectedOrderId; // To display in the modal header

    @track isLoading = true; // Add loading state

    @track sortBy = 'orderId';
    @track sortDirection = 'asc';

    _accountId; // Private property to hold the actual Account ID

    @wire(getRecord, { recordId: '$recordId', fields: [ACCOUNT_ID_FIELD] })
    wiredCase({ error, data }) {
        if (data) {
            this._accountId = data.fields.AccountId.value;
            if (this._accountId) {
                this.fetchAccountAndOrders();
            } else {
                this.accountDetails = undefined;
                this.orders = [];
                this.accountDetailsError = 'This Case is not linked to an Account.';
                this.ordersError = 'This Case is not linked to an Account.';
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Info',
                        message: 'This Case is not linked to an Account, so account details and orders cannot be displayed.',
                        variant: 'info',
                    }),
                );
            }
        } else if (error) {
            this.accountDetailsError = error.body ? error.body.message : error.message;
            this.ordersError = error.body ? error.body.message : error.message;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error loading Case data',
                    message: this.accountDetailsError,
                    variant: 'error',
                }),
            );
        }
    }

    async fetchAccountAndOrders() {
        this.isLoading = true; // Start loading
        if (!this._accountId) {
            this.accountDetailsError = 'No Account ID available to fetch details and orders.';
            this.ordersError = 'No Account ID available to fetch details and orders.';
            this.isLoading = false; // Stop loading
            return;
        }

        try {
            this.accessToken = await authenticate();
            if (!this.accessToken) {
                this.ordersError = 'Authentication failed.';
                this.accountDetailsError = 'Authentication failed.';
                this.isLoading = false; // Stop loading
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Authentication failed. Please check Custom Labels for OAuth credentials.',
                        variant: 'error',
                    }),
                );
                return;
            }

            const accountJson = await getAccountById({ recordId: this._accountId });

            if (accountJson) {
                this.accountDetails = accountJson;
                this.accountDetailsError = undefined;

                const accountEmail = this.accountDetails.PersonEmail;
                if (accountEmail) {
                    const orderDataList = await getOrdersAndDetailsByEmail({ email: accountEmail });
                    this.orders = orderDataList.map(order => ({
                        ...order.orderDetails,
                        orderId: order.orderId,
                        orderItems: order.orderItems
                    }));
                    this.ordersError = undefined;
                } else {
                    this.orders = [];
                    this.ordersError = 'No email found for this account to fetch orders. Please ensure PersonEmail is populated for the account.';
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Info',
                            message: 'No email found for this account to fetch orders. Please ensure PersonEmail is populated for the account.',
                            variant: 'info',
                        }),
                    );
                }
            } else {
                this.accountDetails = undefined;
                this.orders = [];
                this.accountDetailsError = 'Failed to load account details. Account with ID ' + this._accountId + ' might not exist or data is inaccessible.';
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Failed to load account details. Account with ID ' + this._accountId + ' might not exist or data is inaccessible.',
                        variant: 'error',
                    }),
                );
            }

        } catch (error) {
            this.accountDetailsError = error.body ? error.body.message : error.message;
            this.ordersError = error.body ? error.body.message : error.message;
            this.orders = [];
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: `Error loading data: ${this.accountDetailsError || this.ordersError}. Please check Apex logs for getAccountById and getOrdersAndDetailsByEmail.`,
                    variant: 'error',
                }),
            );
        }
        this.isLoading = false; // Stop loading after fetch
    }

    get noOrdersFound() {
        return !this.isLoading && this.orders.length === 0 && !this.ordersError;
    }

    get sortedOrders() {
        if (!this.orders) return [];
        const sorted = [...this.orders];
        sorted.sort((a, b) => {
            let valA = a[this.sortBy];
            let valB = b[this.sortBy];
            // For dates, convert to Date
            if (this.sortBy === 'EffectiveDate') {
                valA = valA ? new Date(valA) : 0;
                valB = valB ? new Date(valB) : 0;
            }
            if (valA === undefined || valA === null) valA = '';
            if (valB === undefined || valB === null) valB = '';
            if (valA < valB) return this.sortDirection === 'asc' ? -1 : 1;
            if (valA > valB) return this.sortDirection === 'asc' ? 1 : -1;
            return 0;
        });
        return sorted;
    }

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        this.sortBy = fieldName;
        this.sortDirection = sortDirection;
    }

    handleOrderRowAction(event) {
        const actionName = event.detail.action ? event.detail.action.name : event.detail.actionName;
        const row = event.detail.row;

        if (actionName === 'view_order_items') {
            const selectedOrder = this.orders.find(order => order.orderId === row.orderId);
            if (selectedOrder && selectedOrder.orderItems) {
                this.modalOrderItems = selectedOrder.orderItems;
                this.selectedOrderId = selectedOrder.orderId; // Set the selected order ID for the modal header
                this.isModalOpen = true; // Open the modal
            } else {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Info',
                        message: 'No order items available for this order.',
                        variant: 'info',
                    }),
                );
            }
        } else if (actionName === 'reorder_order') {
            this.handleReorder(row.orderId);
        } else if (actionName === 'delete_order') {
            this.handleDeleteOrder(row.orderId);
        } else if (actionName === 'refund_order') {
            this.handleRefundOrder(row.orderId);
        } else if (actionName === 'partial_refund_order') {
            this.handlePartialRefundOrder(row.orderId);
        }
    }

    // Function to close the modal
    closeModal() {
        this.isModalOpen = false;
        this.modalOrderItems = []; // Clear items when closing
        this.selectedOrderId = undefined;
    }

    handleReorder(orderId) {
        reorderOrder({ externalOrderId: orderId })
            .then(newOrderId => {
                if (newOrderId) {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Success',
                            message: `Order reordered successfully! New Order ID: ${newOrderId}`,
                            variant: 'success',
                        }),
                    );
                } else {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Error',
                            message: 'Failed to reorder order. Check logs for details.',
                            variant: 'error',
                        }),
                    );
                }
                // Always refresh orders after reorder attempt
                this.fetchAccountAndOrders();
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error reordering order',
                        message: error.body ? error.body.message : error.message,
                        variant: 'error',
                    }),
                );
                // Refresh orders even on error to ensure UI is up to date
                this.fetchAccountAndOrders();
            });
    }

    handleDeleteOrder(orderId) {
        deleteExternalOrder({ externalOrderId: orderId })
            .then(success => {
                if (success) {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Success',
                            message: `Order deleted successfully!`,
                            variant: 'success',
                        }),
                    );
                } else {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Error',
                            message: 'Failed to delete order. Check logs for details.',
                            variant: 'error',
                        }),
                    );
                }
                // Always refresh orders after delete attempt
                this.fetchAccountAndOrders();
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error deleting order',
                        message: error.body ? error.body.message : error.message,
                        variant: 'error',
                    }),
                );
                // Refresh orders even on error to ensure UI is up to date
                this.fetchAccountAndOrders();
            });
    }

    handleRefundOrder(orderId) {
        // Call Apex to set refund status to 'Refund'
        refundStatus({ externalOrderId: orderId, refundStatus: 'Refund' })
            .then(success => {
                if (success) {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Success',
                            message: `Order refunded successfully!`,
                            variant: 'success',
                        }),
                    );
                } else {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Error',
                            message: 'Failed to refund order. Check logs for details.',
                            variant: 'error',
                        }),
                    );
                }
                this.fetchAccountAndOrders();
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error refunding order',
                        message: error.body ? error.body.message : error.message,
                        variant: 'error',
                    }),
                );
                this.fetchAccountAndOrders();
            });
    }

    handlePartialRefundOrder(orderId) {
        // Call Apex to set refund status to 'HalfRefund'
        refundStatus({ externalOrderId: orderId, refundStatus: 'HalfRefund' })
            .then(success => {
                if (success) {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Success',
                            message: `Order partially refunded successfully!`,
                            variant: 'success',
                        }),
                    );
                } else {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Error',
                            message: 'Failed to partially refund order. Check logs for details.',
                            variant: 'error',
                        }),
                    );
                }
                this.fetchAccountAndOrders();
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error partially refunding order',
                        message: error.body ? error.body.message : error.message,
                        variant: 'error',
                    }),
                );
                this.fetchAccountAndOrders();
            });
    }

    // Add this method to handle refresh from orderItemDetails
    handleOrderItemsRefresh() {
        // Reload account and orders
        this.fetchAccountAndOrders().then(() => {
            // After orders are refreshed, update modalOrderItems with latest data
            if (this.selectedOrderId) {
                const selectedOrder = this.orders.find(order => order.orderId === this.selectedOrderId);
                if (selectedOrder && selectedOrder.orderItems) {
                    this.modalOrderItems = selectedOrder.orderItems;
                } else {
                    this.modalOrderItems = [];
                }
            }
        });
    }

    // Pass sort info to modal
    get modalOrderItemSortInfo() {
        return {
            sortBy: this.orderItemSortBy,
            sortDirection: this.orderItemSortDirection
        };
    }
}