import { FAQS } from "@/data/faq";
import {
  APK_URL,
  GITHUB_URL,
  OG_IMAGE_URL,
  SITE_DESCRIPTION,
  SITE_NAME,
  SITE_TITLE,
  SITE_URL,
} from "@/data/site";

function schemaScript(data: Record<string, unknown>) {
  return JSON.stringify(data);
}

export function JsonLd() {
  const website = {
    "@context": "https://schema.org",
    "@type": "WebSite",
    name: SITE_NAME,
    url: SITE_URL,
    description: SITE_DESCRIPTION,
    inLanguage: "zh-CN",
    image: OG_IMAGE_URL,
  };

  const software = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: SITE_NAME,
    applicationCategory: "EducationalApplication",
    operatingSystem: "Android",
    offers: {
      "@type": "Offer",
      price: "0",
      priceCurrency: "CNY",
    },
    description: SITE_DESCRIPTION,
    url: SITE_URL,
    downloadUrl: APK_URL,
    image: OG_IMAGE_URL,
    author: {
      "@type": "Organization",
      name: "vvenv",
      url: GITHUB_URL,
      sameAs: [GITHUB_URL],
    },
    featureList: [
      "拍照识别单词并生成听写列表",
      "系统英文语音逐词朗读",
      "错词本本地追踪与导出",
      "内置中考高考与教材词库",
    ],
    isAccessibleForFree: true,
  };

  const faqPage = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: FAQS.map((item) => ({
      "@type": "Question",
      name: item.q,
      acceptedAnswer: {
        "@type": "Answer",
        text: item.a,
      },
    })),
  };

  const webPage = {
    "@context": "https://schema.org",
    "@type": "WebPage",
    name: SITE_TITLE,
    description: SITE_DESCRIPTION,
    url: SITE_URL,
    isPartOf: { "@type": "WebSite", name: SITE_NAME, url: SITE_URL },
    inLanguage: "zh-CN",
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: schemaScript(website) }}
      />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: schemaScript(software) }}
      />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: schemaScript(faqPage) }}
      />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: schemaScript(webPage) }}
      />
    </>
  );
}
