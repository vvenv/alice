import { useEffect, useRef, useState } from "react";

/**
 * 滚动进入视口时触发渐显动画。
 * 返回 ref 和是否可见状态。
 */
export function useReveal<T extends HTMLElement = HTMLDivElement>(
  options?: IntersectionObserverInit,
) {
  const ref = useRef<T>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setVisible(true);
          observer.unobserve(entry.target);
        }
      },
      { threshold: 0.15, rootMargin: "0px 0px -60px 0px", ...options },
    );

    observer.observe(el);
    return () => observer.disconnect();
  }, [options]);

  return { ref, visible };
}

/**
 * 为带有 .reveal 类的子元素添加交错渐显。
 * 每个子元素按 index * delay 顺序显现。
 */
export function useStaggeredReveal<T extends HTMLElement = HTMLDivElement>(
  itemDelay = 120,
) {
  const ref = useRef<T>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const items = Array.from(el.querySelectorAll<HTMLElement>(".reveal"));
    items.forEach((item) => {
      item.style.transitionDelay = "0ms";
    });

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          items.forEach((item, i) => {
            item.style.transitionDelay = `${i * itemDelay}ms`;
            item.classList.add("is-visible");
          });
          observer.unobserve(entry.target);
        }
      },
      { threshold: 0.1, rootMargin: "0px 0px -40px 0px" },
    );

    observer.observe(el);
    return () => observer.disconnect();
  }, [itemDelay]);

  return ref;
}
