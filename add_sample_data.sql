-- Sample dataset for testing
-- This script creates sample tables and inserts data

-- Create a sample users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) NOT NULL,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT true
);

-- Create a sample products table
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL,
    category VARCHAR(50),
    stock_quantity INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create a sample orders table
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10, 2) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending'
);

-- Create a sample order_items table
CREATE TABLE IF NOT EXISTS order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(id),
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER NOT NULL,
    price DECIMAL(10, 2) NOT NULL
);

-- Insert sample users
INSERT INTO users (username, email, first_name, last_name, is_active) VALUES
    ('john_doe', 'john.doe@example.com', 'John', 'Doe', true),
    ('jane_smith', 'jane.smith@example.com', 'Jane', 'Smith', true),
    ('bob_wilson', 'bob.wilson@example.com', 'Bob', 'Wilson', true),
    ('alice_jones', 'alice.jones@example.com', 'Alice', 'Jones', true),
    ('charlie_brown', 'charlie.brown@example.com', 'Charlie', 'Brown', false)
ON CONFLICT (username) DO NOTHING;

-- Insert sample products
INSERT INTO products (name, description, price, category, stock_quantity) VALUES
    ('Laptop', 'High-performance laptop with 16GB RAM', 1299.99, 'Electronics', 50),
    ('Mouse', 'Wireless optical mouse', 29.99, 'Electronics', 200),
    ('Keyboard', 'Mechanical keyboard with RGB lighting', 89.99, 'Electronics', 75),
    ('Monitor', '27-inch 4K monitor', 399.99, 'Electronics', 30),
    ('Headphones', 'Noise-cancelling headphones', 199.99, 'Electronics', 100),
    ('Desk Chair', 'Ergonomic office chair', 299.99, 'Furniture', 25),
    ('Desk', 'Standing desk with adjustable height', 599.99, 'Furniture', 15),
    ('Lamp', 'LED desk lamp', 49.99, 'Furniture', 80)
ON CONFLICT DO NOTHING;

-- Insert sample orders
INSERT INTO orders (user_id, total_amount, status) VALUES
    (1, 1329.98, 'completed'),
    (2, 89.99, 'pending'),
    (1, 599.99, 'shipped'),
    (3, 229.98, 'completed'),
    (4, 999.97, 'pending')
ON CONFLICT DO NOTHING;

-- Insert sample order items
INSERT INTO order_items (order_id, product_id, quantity, price) VALUES
    (1, 1, 1, 1299.99),
    (1, 2, 1, 29.99),
    (2, 3, 1, 89.99),
    (3, 7, 1, 599.99),
    (4, 2, 1, 29.99),
    (4, 5, 1, 199.99),
    (5, 1, 1, 1299.99),
    (5, 4, 1, 399.99),
    (5, 6, 1, 299.99)
ON CONFLICT DO NOTHING;

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);

-- Display summary
SELECT 'Sample data inserted successfully!' AS message;
SELECT COUNT(*) AS total_users FROM users;
SELECT COUNT(*) AS total_products FROM products;
SELECT COUNT(*) AS total_orders FROM orders;
SELECT COUNT(*) AS total_order_items FROM order_items;
