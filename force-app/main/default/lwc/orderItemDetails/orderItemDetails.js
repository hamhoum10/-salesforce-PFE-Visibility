// OrderItemDetails.js
import { LightningElement, api } from 'lwc';

const COLUMNS = [
    { label: 'Product Name', fieldName: 'ProductName', type: 'text' }, // Will need to derive this from productDetails
    { label: 'Quantity', fieldName: 'quantity', type: 'number' },
    { label: 'Unit Price', fieldName: 'unitPrice', type: 'currency' },
    // Add more fields from OrderItemDetail and productDetails as needed
];

export default class OrderItemDetails extends LightningElement {
    @api orderItems = []; // Public property to receive order items
    columns = COLUMNS; // Columns for the datatable

    // Process orderItems to flatten productDetails for display in the datatable
    get processedOrderItems() {
        return this.orderItems.map(item => ({
            ...item,
            // Assuming 'Name' is a field on Product2 within productDetails
            ProductName: item.productDetails ? item.productDetails.Name : 'N/A'
        }));
    }

    // Getter to determine if there are no processed order items to display
    // This simplifies the conditional rendering logic in the HTML template.
    get noOrderItemsToDisplay() {
        return this.processedOrderItems.length === 0;
    }
}