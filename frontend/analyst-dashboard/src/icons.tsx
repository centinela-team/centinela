type IconProps = { size?: number };

const base = (size = 18) => ({
  width: size,
  height: size,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.8,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
});

export function IconShield({ size }: IconProps) {
  return (
    <svg {...base(size)}>
      <path d="M12 3l7 3v6c0 4.5-3 7.5-7 9-4-1.5-7-4.5-7-9V6l7-3z" />
      <path d="M9 12l2 2 4-4" />
    </svg>
  );
}

export function IconLayers({ size }: IconProps) {
  return (
    <svg {...base(size)}>
      <path d="M12 3l9 5-9 5-9-5 9-5z" />
      <path d="M3 13l9 5 9-5" />
    </svg>
  );
}

export function IconSliders({ size }: IconProps) {
  return (
    <svg {...base(size)}>
      <line x1="4" y1="6" x2="20" y2="6" />
      <circle cx="9" cy="6" r="2" fill="currentColor" stroke="none" />
      <line x1="4" y1="12" x2="20" y2="12" />
      <circle cx="15" cy="12" r="2" fill="currentColor" stroke="none" />
      <line x1="4" y1="18" x2="20" y2="18" />
      <circle cx="7" cy="18" r="2" fill="currentColor" stroke="none" />
    </svg>
  );
}

export function IconRefresh({ size }: IconProps) {
  return (
    <svg {...base(size)}>
      <path d="M4 4v5h5" />
      <path d="M20 20v-5h-5" />
      <path d="M5.5 9a7 7 0 0112-2.5L20 9" />
      <path d="M18.5 15a7 7 0 01-12 2.5L4 15" />
    </svg>
  );
}

export function IconLogout({ size }: IconProps) {
  return (
    <svg {...base(size)}>
      <path d="M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4" />
      <path d="M16 17l5-5-5-5" />
      <path d="M21 12H9" />
    </svg>
  );
}

export function IconUpload({ size }: IconProps) {
  return (
    <svg {...base(size)}>
      <path d="M12 16V4" />
      <path d="M6 10l6-6 6 6" />
      <path d="M4 20h16" />
    </svg>
  );
}

export function IconFile({ size }: IconProps) {
  return (
    <svg {...base(size)}>
      <path d="M7 3h7l5 5v13a1 1 0 01-1 1H7a1 1 0 01-1-1V4a1 1 0 011-1z" />
      <path d="M14 3v5h5" />
    </svg>
  );
}

export function IconAlert({ size }: IconProps) {
  return (
    <svg {...base(size)}>
      <path d="M12 3l10 18H2L12 3z" />
      <line x1="12" y1="10" x2="12" y2="14" />
      <circle cx="12" cy="17" r="0.5" fill="currentColor" />
    </svg>
  );
}

export function IconInbox({ size }: IconProps) {
  return (
    <svg {...base(size)}>
      <path d="M4 12h4l2 3h4l2-3h4" />
      <path d="M5.5 5h13L21 12v6a1 1 0 01-1 1H4a1 1 0 01-1-1v-6L5.5 5z" />
    </svg>
  );
}
