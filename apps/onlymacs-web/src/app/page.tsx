import { HeroContent } from "@/components/HeroContent";
import { HomepageFAQ } from "@/components/HomepageFAQ";
import { ProductComputer } from "@/components/ProductComputer";

export default function Home() {
  return (
    <main className="main-container">
      <HeroContent />
      <ProductComputer />
      <HomepageFAQ />
    </main>
  );
}
