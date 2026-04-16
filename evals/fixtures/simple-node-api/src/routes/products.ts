import { Router } from 'express';
import { prisma } from '../index';

export const productRouter = Router();

productRouter.get('/', async (req, res) => {
  const { category } = req.query;
  // SQL injection possible if using raw queries
  const products = await prisma.product.findMany({
    where: category ? { category: String(category) } : undefined,
  });
  res.json(products);
});

productRouter.post('/', async (req, res) => {
  // No input validation
  const product = await prisma.product.create({ data: req.body });
  res.json(product);
});

productRouter.delete('/:id', async (req, res) => {
  // No auth check — anyone can delete
  await prisma.product.delete({ where: { id: req.params.id } });
  res.json({ ok: true });
});
