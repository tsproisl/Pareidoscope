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
    <!-- incoming dependencies -->
    <xsl:text>|</xsl:text>
    <xsl:for-each select="../../dependencies[@type='collapsed-ccprocessed-dependencies']/dep/dependent[@idx=$tokenid]">
      <xsl:value-of select="../@type"/>
      <xsl:text>(</xsl:text>
      <xsl:value-of select="(../governor/@idx - $tokenid)"/>
      <xsl:value-of select="substring(&quot;''''''''''''''''''''''''''''''''''''''''''''''''''&quot;, 1, ../governor/@copy)"/>
      <xsl:text>,0</xsl:text>
      <!-- <xsl:value-of select="(@idx - $tokenid)"/> -->
      <xsl:value-of select="substring(&quot;''''''''''''''''''''''''''''''''''''''''''''''''''&quot;, 1, @copy)"/>
      <xsl:text>)</xsl:text>
      <xsl:text>|</xsl:text>
    </xsl:for-each>
    <xsl:value-of select="$tab"/>
    <!-- outgoing dependencies -->
    <xsl:text>|</xsl:text>
    <xsl:for-each select="../../dependencies[@type='collapsed-ccprocessed-dependencies']/dep/governor[@idx=$tokenid]">
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
    <xsl:value-of select="$newline"/>
  </xsl:for-each>
</xsl:template>

</xsl:stylesheet>
