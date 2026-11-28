import { defineConfig } from 'vite';
import { viteSingleFile } from 'vite-plugin-singlefile';

export default defineConfig({
  plugins: [viteSingleFile()],
  build: {
    outDir: '../assets/editor',
    emptyOutDir: true,
    minify: 'esbuild',
    target: 'es2020',
  },
});
