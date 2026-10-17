import "./globals.css";

export const metadata = {
 title: "Giveaway Raffle",
 description: "Ikuti giveaway & raffle transparan untuk proyek NFT",
};

export default function RootLayout({ children }) {
 return (
 <html lang="id">
 <head>
 <meta charSet="utf-8" />
 </head>
 <body>
 <div className="container">
 <nav className="nav">
 <a href="/" className="logo">
 {"\u{1F3B0}"} Giveaway<span>Raffle</span>
 </a>
 <a href="/admin" className="btn">
 Admin
 </a>
 </nav>
 {children}
 <div className="footer">
 Giveaway Raffle - undian transparan dengan seed terverifikasi
 </div>
 </div>
 </body>
 </html>
 );
}
