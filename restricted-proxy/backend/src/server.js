const express = require('express');
const bodyParser = require('body-parser');
const compareRoutes = require('./routes/compareRoutes');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(helmet());

app.use(bodyParser.json({ limit: '1mb' }));
app.use(bodyParser.text({ limit: '1mb', type: 'text/plain' }));

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 25 
});
app.use(limiter);

app.use('/api', compareRoutes);

app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
