import "./globals.css";

export const metadata = {
 title: "Giveaway Raffle",
 description: "Join transparent giveaways & raffles for NFT projects",
};

export default function RootLayout({ children }) {
 return (
 <html lang="en">
 <head>
 <meta charSet="utf-8" />
 </head>
 <body>
 <div className="container">
 <nav className="nav">
 <a href="/" className="logo">
 Giveaway<span>Raffle</span>
 </a>
 </nav>
 {children}
 <div className="footer">
 Giveaway Raffle - transparent draws with verifiable seed
 </div>
 </div>
 </body>
 </html>
 );
}