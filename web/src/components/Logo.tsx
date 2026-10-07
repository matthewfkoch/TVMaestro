type LogoProps = {
  title?: string;
  className?: string;
};

export default function Logo({ title = "TVMaestro", className }: LogoProps) {
  return <img className={className} src="/logo.png" alt={title} />;
}
