type LogoProps = {
  size?: number;
  title?: string;
  className?: string;
};

/** Channel spine + EPG bars — guide meets conductor. */
export default function Logo({ size = 28, title = "TVMaestro", className }: LogoProps) {
  return (
    <svg
      className={className}
      width={size}
      height={size}
      viewBox="0 0 32 32"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      role="img"
      aria-label={title}
    >
      <title>{title}</title>
      <rect x="5" y="5" width="5" height="22" rx="2.5" fill="currentColor" />
      <rect x="13" y="5" width="14" height="5" rx="2.5" fill="currentColor" />
      <rect x="13" y="13.5" width="11" height="5" rx="2.5" fill="currentColor" opacity="0.85" />
      <rect x="13" y="22" width="8" height="5" rx="2.5" fill="currentColor" opacity="0.65" />
    </svg>
  );
}
