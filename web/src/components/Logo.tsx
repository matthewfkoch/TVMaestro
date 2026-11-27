type LogoProps = {
  title?: string;
  className?: string;
};

export default function Logo({ title = "TVMaestro", className }: LogoProps) {
  const src = `${import.meta.env.BASE_URL}logo.png`.replace(/\/{2,}/g, "/");
  return <img className={className} src={src} alt={title} />;
}
