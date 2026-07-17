/** @type {import('tailwindcss').Config} */

export default {
  darkMode: "class",
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: {
    container: {
      center: true,
      padding: {
        DEFAULT: "1.5rem",
        lg: "2rem",
        xl: "3rem",
      },
    },
    extend: {
      colors: {
        paper: "#FAF6EE",
        ink: "#1A2B4A",
        rose: "#C44569",
        gold: "#B8860B",
        parchment: "#F2EBDA",
        midnight: "#0F1A2E",
        nightpaper: "#162238",
      },
      fontFamily: {
        display: [
          '"Playfair Display"',
          '"Noto Serif SC"',
          '"Source Han Serif SC"',
          '"Songti SC"',
          "Georgia",
          "serif",
        ],
        serif: [
          '"Cormorant Garamond"',
          '"Noto Serif SC"',
          '"Source Han Serif SC"',
          '"Songti SC"',
          "Georgia",
          "serif",
        ],
        sans: [
          '"Noto Sans SC"',
          '"PingFang SC"',
          '"Hiragino Sans GB"',
          '"Noto Sans CJK SC"',
          '"Microsoft YaHei"',
          "system-ui",
          "sans-serif",
        ],
      },
      letterSpacing: {
        tightest: "-0.04em",
      },
      animation: {
        "spin-slow": "spin 24s linear infinite",
        "spin-slower": "spin 40s linear infinite",
        "float": "float 6s ease-in-out infinite",
        "shimmer": "shimmer 3s ease-in-out infinite",
      },
      keyframes: {
        float: {
          "0%, 100%": { transform: "translateY(0px)" },
          "50%": { transform: "translateY(-12px)" },
        },
        shimmer: {
          "0%, 100%": { opacity: "0.4" },
          "50%": { opacity: "0.9" },
        },
      },
    },
  },
  plugins: [],
};
