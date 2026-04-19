const express = require('express');
const bodyParser = require('body-parser');
const mysql = require('mysql');
const mongoose = require('mongoose');

const app = express();
app.use(bodyParser.json());
app.set('view engine', 'ejs');

// Two databases — no clear reason
const sqlConn = mysql.createConnection({
  host: 'localhost',
  user: 'root',
  password: 'password123',
  database: 'myapp'
});

mongoose.connect('mongodb://localhost/myapp');

// SQL injection vulnerability
app.get('/users', (req, res) => {
  const name = req.query.name;
  sqlConn.query("SELECT * FROM users WHERE name = '" + name + "'", (err, results) => {
    if (err) return res.status(500).send(err.message);
    res.json(results);
  });
});

// Mixed concerns — business logic in route handler
app.post('/orders', (req, res) => {
  const { userId, items } = req.body;
  let total = 0;
  items.forEach(item => {
    total += item.price * item.quantity;
    if (item.quantity > 100) total *= 0.9; // 10% discount
  });
  sqlConn.query(
    "INSERT INTO orders (user_id, total, items) VALUES ('" + userId + "', " + total + ", '" + JSON.stringify(items) + "')",
    (err) => {
      if (err) return res.status(500).send(err.message);
      res.json({ total });
    }
  );
});

app.listen(3000);
