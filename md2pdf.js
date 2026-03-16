const { mdToPdf } = require('md-to-pdf');
const path = require('path');

const mdPath = path.join(__dirname, 'AXM-CLIENT-SERVER-SETUP.md');
const pdfPath = path.join(__dirname, 'AXM-CLIENT-SERVER-SETUP.pdf');
const cssPath = path.join(__dirname, 'pdf-style.css');

mdToPdf(
  { path: mdPath },
  {
    dest: pdfPath,
    stylesheet: cssPath,
    pdf_options: {
      format: 'A4',
      margin: { top: '25mm', right: '25mm', bottom: '28mm', left: '25mm' },
      printBackground: true,
      displayHeaderFooter: true,
      footerTemplate: '<div style="font-size:9px; color:#666; width:100%; text-align:center;">— <span class="pageNumber"></span> of <span class="totalPages"></span> —</div>',
      headerTemplate: '<div></div>',
    },
    launch_options: {
      executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
      args: ['--no-sandbox', '--disable-setuid-sandbox'],
    },
  }
)
  .then(() => console.log('PDF saved to', pdfPath))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
