module.exports = {
  content: [
    './app/views/**/*.{erb,html}',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.{js,jsx}',
    './app/components/**/*.{rb,erb,html,jsx}'
  ],
  theme: {
    extend: {},
  },
  plugins: [
    require('tailwindcss-animate')
  ],
}
