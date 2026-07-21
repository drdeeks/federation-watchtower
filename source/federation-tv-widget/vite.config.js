import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  root: 'src',
  build: {
    outDir: '../public/react-dist',
    emptyOutDir: true,
    rollupOptions: {
      input: 'react/main.tsx',
      output: {
        entryFileNames: 'assets/office-stage.js',
        chunkFileNames: 'assets/[name].js',
        assetFileNames: 'assets/[name].[ext]',
      },
    },
  },
});
