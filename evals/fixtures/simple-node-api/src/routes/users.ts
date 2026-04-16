import { Router } from 'express';
import { prisma } from '../index';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';

export const userRouter = Router();

userRouter.post('/register', async (req, res) => {
  const { email, password, name } = req.body;
  const hashed = await bcrypt.hash(password, 10);
  const user = await prisma.user.create({
    data: { email, password: hashed, name },
  });
  res.json({ id: user.id, email: user.email });
});

userRouter.post('/login', async (req, res) => {
  const { email, password } = req.body;
  const user = await prisma.user.findUnique({ where: { email } });
  if (!user || !(await bcrypt.compare(password, user.password))) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }
  // JWT_SECRET hardcoded — security issue
  const token = jwt.sign({ userId: user.id }, 'my-secret-key-123');
  res.json({ token });
});

userRouter.get('/', async (_req, res) => {
  // No pagination — performance issue at scale
  const users = await prisma.user.findMany();
  res.json(users);
});
