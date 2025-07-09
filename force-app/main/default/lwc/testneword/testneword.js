import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Import Apex methods
import getOrdersAndDetailsByEmail from '@salesforce/apex/omri.getOrdersAndDetailsByEmail';
import refundStatus from '@salesforce/apex/omri.refundStatus';
// import updateExternalOrderItems from '@salesforce/apex/omri.updateExternalOrderItems'; // Uncomment if needed
// import reorderOrder from '@salesforce/apex/omri.reorderOrder'; // Uncomment if needed
export default class Testneword extends LightningElement {
   @track customerEmail = '';
    @track orders = [];
    @track isLoading = false;
    @track ordersFound = false;
    @track noOrdersFound = false;
    @track hasError = false;
    @track errorMessage = '';

    // Options for refund status combobox
    refundStatusOptions = [
        { label: 'No Refund', value: 'NoRefund' },
        { label: 'Refund', value: 'Refund' },
        { label: 'Half Refund', value: 'HalfRefund' },
        { label: 'Exchange', value: 'Exchange' },
    ];

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

        try {
            const result = await getOrdersAndDetailsByEmail({ email: this.customerEmail });
            if (result && result.length > 0) {
                // Initialize selectedRefundStatus for each order
                this.orders = result.map(order => ({
                    ...order,
                    selectedRefundStatus: order.orderDetails.Refund_Status__c || 'NoRefund' // Default to NoRefund
                }));
                this.ordersFound = true;
            } else {
                this.noOrdersFound = true;
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

    handleRefundStatusChange(event) {
        const orderId = event.target.dataset.orderId; // Get orderId from data-order-id
        const value = event.detail.value;

        this.orders = this.orders.map(order => {
            if (order.orderId === orderId) {
                return { ...order, selectedRefundStatus: value };
            }
            return order;
        });
    }

    async handleUpdateRefundStatus(event) {
        const orderId = event.target.dataset.orderId; // Get orderId from data-order-id
        const status = event.target.dataset.status;   // Get status from data-status

        if (!orderId || !status) {
            this.showToast('Error', 'Order ID or status is missing for update.', 'error');
            return;
        }

        this.isLoading = true;
        try {
            const success = await refundStatus({ externalOrderId: orderId, refundStatus: status });
            if (success) {
                this.showToast('Success', `Refund status for order ${orderId} updated to ${status}.`, 'success');
                // Refresh orders to reflect the change
                await this.handleFetchOrders();
            } else {
                this.showToast('Error', `Failed to update refund status for order ${orderId}.`, 'error');
            }
        } catch (error) {
            this.errorMessage = error.body ? error.body.message : error.message;
            console.error('Error updating refund status:', error);
            this.showToast('Error', 'Failed to update refund status: ' + this.errorMessage, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // --- Examples for other Apex methods (uncomment and adapt as needed) ---

    /*
    async handleUpdateOrderItems(orderItemsToUpdate) { // orderItemsToUpdate would be a list of OrderItem sObjects
        this.isLoading = true;
        try {
            const resultsMap = await updateExternalOrderItems({ localItemsToUpdate: orderItemsToUpdate });
            // Process resultsMap to see which items succeeded/failed
            this.showToast('Success', 'Order items update initiated.', 'success');
            // Logic to refresh display based on resultsMap
        } catch (error) {
            console.error('Error updating order items:', error);
            this.showToast('Error', 'Failed to update order items: ' + (error.body ? error.body.message : error.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleReorder(originalOrderId) {
        this.isLoading = true;
        try {
            const newOrderId = await reorderOrder({ externalOrderId: originalOrderId });
            if (newOrderId) {
                this.showToast('Success', `Order reordered successfully. New Order ID: ${newOrderId}`, 'success');
                // You might want to clear the form or fetch the new order details
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
    */

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(event);
    }
}