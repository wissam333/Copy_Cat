import { defineConfig } from 'vite';

// Build as a single classic-JS bundle (IIFE) with relative asset URLs:
// the built demo then works by double-clicking dist/index.html offline
// (file://) AND on GitHub Pages subpaths — no server needed in either.
export default defineConfig({
  base: './',
  build: {
    outDir: '../dist',
    emptyOutDir: true,
    modulePreload: false,
    rollupOptions: {
      output: {
        format: 'iife',
        entryFileNames: 'assets/score.js',
      },
    },
  },
});
