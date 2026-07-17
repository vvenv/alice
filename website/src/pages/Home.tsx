import { Navbar } from "@/components/Navbar";
import { Hero } from "@/components/Hero";
import { Features } from "@/components/Features";
import { Showcase } from "@/components/Showcase";
import { Workflow } from "@/components/Workflow";
import { Download } from "@/components/Download";
import { Faq } from "@/components/Faq";
import { Footer } from "@/components/Footer";
import { JsonLd } from "@/components/JsonLd";

export default function Home() {
  return (
    <div className="relative min-h-screen overflow-x-hidden">
      <JsonLd />
      <Navbar />
      <main>
        <Hero />
        <Features />
        <Showcase />
        <Workflow />
        <Download />
        <Faq />
      </main>
      <Footer />
    </div>
  );
}
