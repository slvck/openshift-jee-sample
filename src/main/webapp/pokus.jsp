<%@ page contentType="text/html;charset=iso-8859-1"  errorPage="/error.jsp" %>

<%@ page  import="java.io.BufferedInputStream" %>
<%@ page  import="java.io.ByteArrayOutputStream" %>
<%@ page  import="java.io.InputStream" %>
<%@ page  import="java.net.Authenticator" %>
<%@ page  import="java.net.PasswordAuthentication" %>
<%@ page  import="java.net.URL" %>
<%@ page  import="java.net.URLConnection" %>
<%@ page  import="java.util.ArrayList" %>
<%@ page  import="java.util.Arrays" %>
<%@ page  import="java.util.List" %>
<%@ page  import="java.util.concurrent.Callable" %>
<%@ page  import="java.util.concurrent.CancellationException" %>
<%@ page  import="java.util.concurrent.ExecutionException" %>
<%@ page  import="java.util.concurrent.ExecutorService" %>
<%@ page  import="java.util.concurrent.Executors" %>
<%@ page  import="java.util.concurrent.Future" %>
<%@ page  import="java.util.concurrent.TimeUnit" %>
<%@ page  import="java.util.concurrent.TimeoutException" %>
<%@ page  import="java.util.regex.Matcher" %>
<%@ page  import="java.util.regex.Pattern" %>

<%!

  /**
   * Pretransformuje danou stranku do tvaru vhodneho pro opera mini
   * @param str stranka v puvodnim tvaru, vracena z 
   * http://www.snow-forecast.com/resorts/???/3dayfree
   * @return stranku vhodnou pro mobil
   */
  static String transformSnowForecast(final String str) {
    try {
      String actStr = str;
      final String[] regexs = {".*(< *table.*< */ *table *>).*< *table.*"};
      for (final String regex : regexs) {
        final Pattern pat = Pattern.compile(regex, Pattern.DOTALL);
        final Matcher mat = pat.matcher(actStr);
        if (!mat.matches()) {
          throw new IllegalArgumentException("Neodpovida " + regex);
        } else {
          actStr = mat.group(1);
        }
      }
      actStr = actStr.replaceAll("< *table[^>]*>", "<table border='1px' cellspacing='0px' cellpadding='2px'>");
      actStr = actStr.replaceAll("< *div[^>]*>","");
      actStr = actStr.replaceAll("< */ *div[^>]*>","");
      actStr = actStr.replaceAll("< *DIV[^>]*>","");
      actStr = actStr.replaceAll("< */ *DIV[^>]*>","");
      actStr = actStr.replaceAll("< *font[^>]*>","");
      actStr = actStr.replaceAll("< */ *font[^>]*>","");
      actStr = actStr.replaceAll("< *FONT[^>]*>","");
      actStr = actStr.replaceAll("< */ *FONT[^>]*>","");
      actStr = actStr.replaceAll("< *td[^>]*>","<td>");
      actStr = actStr.replaceAll("< *TD[^>]*>","<TD>");
      actStr = actStr.replaceAll("http://www.snow-forecast.com/wxicons/daythunderstorm.gif","http://www.clipartbest.com/cliparts/9c4/k9A/9c4k9AzcE.png");
      return actStr;
    } catch (Exception ex) {
      ex.printStackTrace();
      return exToErrHTML(ex);
    }
  }

  /**
   * Obali chybove hlaseni tak aby tvoril kus html kodu s hlasenim o chybe
   * @param ex vyjimka ze ktereho se ma ta stranka udelat
   * @return kus html kodu obsahujici dane chybove hlaseni
   */
  private static String exToErrHTML(final Exception ex) {
    if (ex == null) {
      throw new NullPointerException("ex == null");
    } else {
      return "" + ex.getMessage() + "";
    }  
  }

  /**
   * Zapouzdruje vysledek jednoho dotazu na http(s) server
   */
  static final class VysledekStazeni {
    /** Navratovy kod htp serveru (0 znamena nejakou exception) */
    final int retval;
    /** stranka jako jeden retezec */
    final String content;

    /**
     * Prevezme dane parametry
     */
    VysledekStazeni(final int retval, final String content) {
      this.retval = retval;
      if (content == null) {
        this.content = "";
      } else {
        this.content = content;
      }
    }
  }

  /**
   * rozhrani na transformovani vysledku
   */
  static interface Transformer {
    /**
     * @param str obsah stranky stazen yze serveru 
     * @return kus html zaclenitelny do moji stranky obsahujici data ze str
     */
    String transform(String str); 
  }
%>
<html>
<head>
<META HTTP-EQUIV="CACHE-CONTROL" CONTENT="NO-CACHE">
</head>
<body>
<%
final String[] sfnames = {
        "CH Andermatt", 
        "CH St-Moritz", 
        "AT Turracherhohe [Nockalm]",
        "AT Heiligenblut [Glock]",
        "AT Solden", 
        "IT Cortina", 
        "IT Predazzo",
        "IT Bormio", 
        "IT Sulden",
        "FR Alpe-d-Huez", 
        "FR Briancon", 
};
if (("slavik").equals(request.getParameter("sourceform"))) {
    final String pwd = request.getParameter("password");
    if (!("fflgrt").equalsIgnoreCase("" + pwd)) {
        throw new IllegalArgumentException("pwd");
    }
    if (System.getProperty("http.proxyUser") != null && System.getProperty("http.proxyPassword") != null) {
      Authenticator.setDefault(new Authenticator() {
        protected PasswordAuthentication getPasswordAuthentication() {
          return new PasswordAuthentication (
                  System.getProperty("http.proxyUser"), 
                  System.getProperty("http.proxyPassword").toCharArray());
        }
      });
    }
    //-----------------------------------------------
    final List<String> names = new ArrayList<String>();
    final List<String> urls = new ArrayList<String>();
    final List<Transformer> transformers = new ArrayList<Transformer>();
    Arrays.sort(sfnames);
    final boolean downloadAll = ("true").equals(request.getParameter("snowForecastDownloadAll"));
    for (final String name : sfnames) {
        if (downloadAll || ("true").equals(request.getParameter("snowForecast" + name.replaceAll("[^a-zA-Z]", "")))) {
            names.add(name);
            final String urlName = name.substring(name.indexOf(" ") + 1)
                    .replaceAll(" .*", "");
            urls.add("http://www.snow-forecast.com/resorts/" + urlName + "/3dayfree");
            transformers.add(new Transformer() {
                public String transform(final String str) {
                    return transformSnowForecast(str);
                }
            });
        }
    }  
    if (urls.size() <= 0) {
        out.println("Neni pozadovano stazeni zadnych dat<br>");
    } else {
        final List<Future<String>> futrs = new ArrayList<Future<String>>();
        final ExecutorService exSvc = Executors.newFixedThreadPool(urls.size());
        for (final String urlStr : urls) {
            final Callable<String> c = new Callable<String>() {
                public String call() {
                  try {
                    final URL url = new URL(urlStr);
                    final URLConnection conn = url.openConnection();
                    conn.connect();
                    final InputStream in = new BufferedInputStream(conn.getInputStream());
                    final ByteArrayOutputStream bos = new ByteArrayOutputStream();
                    for (int b = in.read(); b >= 0; b = in.read()) {
                      bos.write(b);
                    }
                    return new String(bos.toByteArray(), "utf-8");
                  } catch (Exception ex) {
                    ex.printStackTrace();
                    return exToErrHTML(ex);
                  }
                }
            };
            futrs.add(exSvc.submit(c));
        }
        for (int i = 0; i < futrs.size(); i++) {
            final Future<String> futr = futrs.get(i);
            VysledekStazeni v = null;
            try {
              v = new VysledekStazeni(200, futr.get(60, TimeUnit.SECONDS));
            } catch (CancellationException ex) {
              v = new VysledekStazeni(0, exToErrHTML(new RuntimeException("Interrupted I")));
            } catch (InterruptedException ex) {
              v = new VysledekStazeni(0, exToErrHTML(new RuntimeException("Interrupted II")));
            } catch (TimeoutException ex) {
              v = new VysledekStazeni(0, exToErrHTML(new RuntimeException("Timed out")));
            } catch (Exception ex) {
              ex.printStackTrace(); 
              v = new VysledekStazeni(0, exToErrHTML(ex));
            }
            out.println("<b>"+names.get(i)+"</b><br>");
            if (v == null) {
                out.println("null<br>");
            } else {
                out.println(transformers.get(i).transform(v.content) + "<br><hr>");
            }
        }
    }
}
%>
<form method="post">
<input type="hidden" name="sourceform" value="slavik">
<input type="text" name="password"><br>
<input type="checkbox" name="snowForecastDownloadAll" value="true"> Download all<br>
<hr/>
<%
for (final String name : sfnames) {
    final String cbName = "snowForecast" + name.replaceAll("[^a-zA-Z]", "");
    %>
    <input type="checkbox" name="<%=cbName%>" value="true"> <%=name%><br>
    <%
}
%>
<input type="submit">
</form>
</body>
</html>
