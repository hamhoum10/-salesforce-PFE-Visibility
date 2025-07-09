// AccountDetailsAndOrders.js
import { LightningElement, api, track } from 'lwc';
import getOrdersAndDetailsByEmail from '@salesforce/apex/omri.getOrdersAndDetailsByEmail';
import reorderOrder from '@salesforce/apex/omri.reorderOrder';
import getAccountById from '@salesforce/apex/omri.getAccountById';
import authenticate from '@salesforce/apex/omri.authenticate';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const ORDER_COLUMNS = [
    { label: 'Order ID', fieldName: 'orderId', type: 'button', typeAttributes: { label: { fieldName: 'orderId' }, name: 'view_order_items', variant: 'base' } },
    { label: 'Status', fieldName: 'Order_Status__c', type: 'text' },
    { label: 'Effective Date', fieldName: 'EffectiveDate', type: 'date' },
    {
        type: 'action',
        typeAttributes: { rowActions: [{ label: 'Reorder', name: 'reorder_order' }] },
    },
];

export default class AccountDetailsAndOrders extends LightningElement {
    @api accountId; // Public property to receive account ID
    @track accountDetails; // Reactive property for account details
    @track accountDetailsError; // Reactive property for account details error
    @track orders = []; // Reactive property for orders list
    @track ordersError; // Reactive property for orders error
    orderColumns = ORDER_COLUMNS; // Columns for the orders datatable
    @track accessToken; // Reactive property for authentication token

    // Lifecycle hook: called when the component is inserted into the DOM
    connectedCallback() {
        this.fetchAccountAndOrders();
    }

    // Getter to determine if no orders are found, simplifying HTML logic
    get noOrdersFound() {
        return this.orders.length === 0;
    }

    // Asynchronously fetches account details and associated orders
    async fetchAccountAndOrders() {
        try {
            // Authenticate to get an access token
            this.accessToken = await authenticate();
            if (!this.accessToken) {
                this.ordersError = 'Authentication failed.';
                this.accountDetailsError = 'Authentication failed.';
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Authentication failed. Please check Custom Labels for OAuth credentials.',
                        variant: 'error',
                    }),
                );
                return; // Exit if authentication fails
            }

            // Construct the API URL for fetching account details
            // Ensure the URL is correct for your Salesforce instance and API version
            const accountApiUrl = 'https://pwcsandbox53-dev-ed.develop.my.salesforce.com/services/data/v63.0/sobjects/Account/';
            // Fetch external account record JSON by ID
            // Make sure the fields being queried by getExternalRecordJsonById include PersonEmail
            const accountJson = await getAccountById({ recordId: this.accountId });
            // await getExternalRecordJsonById({ externalInstanceUrl: accountApiUrl, recordId: this.accountId, accessToken: this.accessToken });

            if (accountJson) {
                this.accountDetails = accountJson; // Parse the JSON string to an object
                this.accountDetailsError = undefined; // Clear any previous account details error

                // Ensure PersonEmail is correctly retrieved and exists
                const accountEmail = this.accountDetails.PersonEmail;
                if (accountEmail) {
                    // Fetch orders based on the account email
                    const orderDataList = await getOrdersAndDetailsByEmail({ email: accountEmail });
                    this.orders = orderDataList.map(order => ({
                        // Flatten order details and add orderId and orderItems for datatable
                        ...order.orderDetails,
                        orderId: order.orderId,
                        orderItems: order.orderItems
                    }));
                    this.ordersError = undefined; // Clear any previous orders error
                } else {
                    this.orders = []; // No orders if no email
                    this.ordersError = 'No email found for this account to fetch orders. Please ensure PersonEmail is populated for the account.';
                    this0.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Info',
                            message: 'No email found for this account to fetch orders. Please ensure PersonEmail is populated for the account.',
                            variant: 'info',
                        }),
                    );
                }
            } else {
                this.accountDetails = undefined; // Clear account details if not found
                this.accountDetailsError = 'Failed to load account details. Account with ID ' + this.accountId + ' might not exist or data is inaccessible.';
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Failed to load account details. Account with ID ' + this.accountId + ' might not exist or data is inaccessible.',
                        variant: 'error',
                    }),
                );
            }

        } catch (error) {
            // Handle any errors during the fetch process
            this.accountDetailsError = error.body ? error.body.message : error.message;
            this.ordersError = error.body ? error.body.message : error.message;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: `Error loading data: ${this.accountDetailsError || this.ordersError}. Please check Apex logs for getExternalRecordJsonById and getOrdersAndDetailsByEmail.`,
                    variant: 'error',
                }),
            );
        }
    }

    // Handles row actions in the orders datatable
    handleOrderRowAction(event) {
        const actionName = event.detail.action.name; // Get the name of the action
        const row = event.detail.row; // Get the row data

        if (actionName === 'view_order_items') {
            const selectedOrder = this.orders.find(order => order.orderId === row.orderId);
            if (selectedOrder && selectedOrder.orderItems) {
                // Dispatch event to show order items
                this.dispatchEvent(new CustomEvent('vieworderitems', {
                    detail: { orderItems: selectedOrder.orderItems }
                }));
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
            this.handleReorder(row.orderId); // Call reorder function
        }
    }

    // Handles reordering an order
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
                    this.fetchAccountAndOrders(); // Refresh the order list after reorder
                } else {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Error',
                            message: 'Failed to reorder order. Check logs for details.',
                            variant: 'error',
                        }),
                    );
                }
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error reordering order',
                        message: error.body ? error.body.message : error.message,
                        variant: 'error',
                    }),
                );
            });
    }
}