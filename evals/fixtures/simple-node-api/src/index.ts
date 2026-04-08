import express from 'express';
import cors from 'cors';
import { PrismaClient } from '@prisma/client';
import { userRouter } from './routes/users';
import { productRouter } from './routes/products';

const app = express();
const prisma = new PrismaClient();

app.use(cors());
app.use(express.json());

app.use('/api/users', userRouter);
app.use('/api/products', productRouter);

app.listen(3000, () => {
  console.log('Server running on port 3000');
});

export { prisma };
