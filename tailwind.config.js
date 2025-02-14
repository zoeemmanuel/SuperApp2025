/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './app/views/**/*.{erb,html}',
    './app/javascript/**/*.{js,jsx}',
    './app/**/*.{erb,html,js,jsx}'
  ],
  theme: {
    extend: {},
  },
  plugins: []
}
