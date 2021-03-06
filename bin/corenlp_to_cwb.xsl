<?xml version="1.0" encoding="UTF-8"?>

<xsl:stylesheet version="1.0"
		xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  
  <xsl:output method="xml" encoding="UTF-8"/>
  
  <xsl:variable name="newline">
    <xsl:text>
</xsl:text>
  </xsl:variable>
  
  <xsl:variable name="tab">
    <xsl:text>	</xsl:text>
  </xsl:variable>
  
  <xsl:template match="/">
    <corpus>
      <xsl:value-of select="$newline"/>
      <text>
	<xsl:value-of select="$newline"/>
	
	<xsl:for-each select="root/document/sentences/sentence">
	  <xsl:apply-templates select=".">
            <xsl:with-param name="position" select="position()"/>
	  </xsl:apply-templates>
	</xsl:for-each>
	
      </text>
      <xsl:value-of select="$newline"/>
    </corpus>
  </xsl:template>
  
  <xsl:template match="root/document/sentences/sentence">
    <xsl:param name="position" select="'0'"/>
    <sentence id="s-{$position}">
      <xsl:value-of select="$newline"/>
      <xsl:apply-templates select="tokens"/>
      
    </sentence>
    <xsl:value-of select="$newline"/>
  </xsl:template>
  
  <xsl:template match="tokens">
    <xsl:for-each select="token">
      <xsl:variable name="tokenid">
	<xsl:value-of select="@id"/>
      </xsl:variable>
      <xsl:value-of select="word"/>
      <xsl:value-of select="$tab"/>
      <xsl:value-of select="POS"/>
      <xsl:value-of select="$tab"/>
      <xsl:value-of select="lemma"/>
      <xsl:value-of select="$tab"/>
      <!-- word class -->
      <xsl:choose>
      	<xsl:when test="POS='CD' or POS='JJ' or POS='JJR' or POS='JJS'">
      	  <xsl:text>ADJ</xsl:text>
      	</xsl:when>
      	<xsl:when test="POS='RB' or POS='RBR' or POS='RBS' or POS='RP' or POS='WRB'">
      	  <xsl:text>ADV</xsl:text>
      	</xsl:when>
      	<xsl:when test="POS='CC' or POS='IN' or POS='TO'">
      	  <xsl:text>CONJ/PREP</xsl:text>
      	</xsl:when>
      	<xsl:when test="POS='DT' or POS='PDT'">
      	  <xsl:text>DET</xsl:text>
      	</xsl:when>
      	<xsl:when test="POS='UH'">
      	  <xsl:text>INTERJ</xsl:text>
      	</xsl:when>
      	<xsl:when test="POS='EX' or POS='PRP' or POS='PRP$' or POS='WDT' or POS='WP' or POS='WP$'">
      	  <xsl:text>PRON</xsl:text>
      	</xsl:when>
      	<xsl:when test="POS=&quot;''&quot; or POS='(' or POS=')' or POS='[' or POS=']' or POS='{' or POS='}' or POS=',' or POS='.' or POS=':' or POS='``' or POS='-LRB-' or POS='-RRB-' or POS='-LSB-' or POS='-RSB-' or POS='-LCB-' or POS='-RCB-' or POS='HYPH' or POS='NFP'">
      	  <xsl:text>PUNC</xsl:text>
      	</xsl:when>
      	<xsl:when test="POS='NN' or POS='NNP' or POS='NNPS' or POS='NNS'">
      	  <xsl:text>SUBST</xsl:text>
      	</xsl:when>
      	<xsl:when test="POS='#' or POS='$' or POS='AFX' or POS='FW' or POS='LS' or POS='POS' or POS='SYM' or POS='XX'">
      	  <xsl:text>UNC</xsl:text>
      	</xsl:when>
      	<xsl:when test="POS='MD' or POS='VB' or POS='VBD' or POS='VBG' or POS='VBN' or POS='VBP' or POS='VBZ'">
      	  <xsl:text>VERB</xsl:text>
      	</xsl:when>
      	<xsl:otherwise>
      	  <xsl:text>UNKNOWN</xsl:text>
      	</xsl:otherwise>
      </xsl:choose>
      <xsl:value-of select="$tab"/>
      <!-- incoming dependencies -->
      <xsl:text>|</xsl:text>
      <xsl:for-each select="../../dependencies[@type='enhanced-plus-plus-dependencies']/dep/dependent[@idx=$tokenid]">
	<xsl:if test="../governor/@idx > 0">
	  <xsl:value-of select="../@type"/>
	  <xsl:text>(</xsl:text>
	  <xsl:value-of select="(../governor/@idx - $tokenid)"/>
	  <xsl:value-of select="substring(&quot;''''''''''''''''''''''''''''''''''''''''''''''''''&quot;, 1, ../governor/@copy)"/>
	  <xsl:text>,0</xsl:text>
	  <!-- <xsl:value-of select="(@idx - $tokenid)"/> -->
	  <xsl:value-of select="substring(&quot;''''''''''''''''''''''''''''''''''''''''''''''''''&quot;, 1, @copy)"/>
	  <xsl:text>)</xsl:text>
	  <xsl:text>|</xsl:text>
	</xsl:if>
      </xsl:for-each>
      <xsl:value-of select="$tab"/>
      <!-- outgoing dependencies -->
      <xsl:text>|</xsl:text>
      <xsl:for-each select="../../dependencies[@type='enhanced-plus-plus-dependencies']/dep/governor[@idx=$tokenid]">
	<xsl:value-of select="../@type"/>
	<xsl:text>(0</xsl:text>
	<!-- <xsl:value-of select="(@idx - $tokenid)"/> -->
	<xsl:value-of select="substring(&quot;''''''''''''''''''''''''''''''''''''''''''''''''''&quot;, 1, @copy)"/>
	<xsl:text>,</xsl:text>
	<xsl:value-of select="(../dependent/@idx - $tokenid)"/>
	<xsl:value-of select="substring(&quot;''''''''''''''''''''''''''''''''''''''''''''''''''&quot;, 1, ../dependent/@copy)"/>
	<xsl:text>)</xsl:text>
	<xsl:text>|</xsl:text>
      </xsl:for-each>
      <xsl:value-of select="$tab"/>
      <!-- root -->
      <xsl:for-each select="../../dependencies[@type='enhanced-plus-plus-dependencies']/dep/dependent[@idx=$tokenid]">
	<xsl:if test="../governor/@idx = 0">
	  <xsl:text>root</xsl:text>
	</xsl:if>
      </xsl:for-each>
      <!-- universal pos tags v. 1.03 -->
      <!-- <xsl:value-of select="$tab"/> -->
      <!-- <xsl:choose> -->
      <!-- 	<xsl:when test="POS='``' or POS='!' or POS='#' or POS='$' or POS=&quot;''&quot; or POS='(' or POS=')' or POS=',' or POS='-LRB-' or POS='-RRB-' or POS='.' or POS=':' or POS='?'"> -->
      <!-- 	  <xsl:text>.</xsl:text> -->
      <!-- 	</xsl:when> -->
      <!-- 	<xsl:when test="POS='JJ' or POS='JJR' or POS='JJRJR' or POS='JJS' or POS='JJ|RB' or POS='JJ|VBG'"> -->
      <!-- 	  <xsl:text>ADJ</xsl:text> -->
      <!-- 	</xsl:when> -->
      <!-- 	<xsl:when test="POS='IN' or POS='IN|RP'"> -->
      <!-- 	  <xsl:text>ADP</xsl:text> -->
      <!-- 	</xsl:when> -->
      <!-- 	<xsl:when test="POS='RB' or POS='RBR' or POS='RBS' or POS='RB|RP' or POS='RB|VBG' or POS='WRB'"> -->
      <!-- 	  <xsl:text>ADV</xsl:text> -->
      <!-- 	</xsl:when> -->
      <!-- 	<xsl:when test="POS='CC'"> -->
      <!-- 	  <xsl:text>CONJ</xsl:text> -->
      <!-- 	</xsl:when> -->
      <!-- 	<xsl:when test="POS='DT' or POS='EX' or POS='PDT' or POS='WDT'"> -->
      <!-- 	  <xsl:text>DET</xsl:text> -->
      <!-- 	</xsl:when> -->
      <!-- 	<xsl:when test="POS='NN' or POS='NNP' or POS='NNPS' or POS='NNS' or POS='NN|NNS' or POS='NN|SYM' or POS='NN|VBG' or POS='NP'"> -->
      <!-- 	  <xsl:text>NOUN</xsl:text> -->
      <!-- 	</xsl:when> -->
      <!-- 	<xsl:when test="POS='CD'"> -->
      <!-- 	  <xsl:text>NUM</xsl:text> -->
      <!-- 	</xsl:when> -->
      <!-- 	<xsl:when test="POS='PRP' or POS='PRP$' or POS='PRP|VBP' or POS='WP' or POS='WP$'"> -->
      <!-- 	  <xsl:text>PRON</xsl:text> -->
      <!-- 	</xsl:when> -->
      <!-- 	<xsl:when test="POS='POS' or POS='PRT' or POS='RP' or POS='TO'"> -->
      <!-- 	  <xsl:text>PRT</xsl:text> -->
      <!-- 	</xsl:when> -->
      <!-- 	<xsl:when test="POS='MD' or POS='VB' or POS='VBD' or POS='VBD|VBN' or POS='VBG' or POS='VBG|NN' or POS='VBN' or POS='VBP' or POS='VBP|TO' or POS='VBZ' or POS='VP'"> -->
      <!-- 	  <xsl:text>VERB</xsl:text> -->
      <!-- 	</xsl:when> -->
      <!-- 	<xsl:when test="POS='CD|RB' or POS='FW' or POS='LS' or POS='RN' or POS='SYM' or POS='UH' or POS='WH'"> -->
      <!-- 	  <xsl:text>X</xsl:text> -->
      <!-- 	</xsl:when> -->
      <!-- 	<xsl:otherwise> -->
      <!-- 	  <xsl:text>UNKNOWN</xsl:text> -->
      <!-- 	</xsl:otherwise> -->
      <!-- </xsl:choose> -->
      <xsl:value-of select="$newline"/>
    </xsl:for-each>
  </xsl:template>
  
</xsl:stylesheet>
