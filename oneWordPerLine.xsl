<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
  
  <!-- This example stylesheet converts a  BNC text for input to a simple
       database system. It outputs one word or punctuation string per line,
       together with a canonical reference for the word, its POS codes, and
       its lemma. The xsl variable sep, defaulting to tab, is used to
       separate values. -->
  
  <xsl:variable name="sep"><xsl:text>&#x09;</xsl:text></xsl:variable>
  
  <xsl:output method="text" encoding="utf-8" />
  
  <xsl:template match="teiHeader"/> <!-- ignore the header -->
  <xsl:template match="text()"/> <!-- suppress any white space -->
  
  <xsl:template match="wtext|stext">
    <xsl:apply-templates/>  <!-- just process the text -->
  </xsl:template>
  
  <xsl:template match="w|c"> 
    <xsl:value-of select="ancestor::bncDoc/@xml:id"/>
    <xsl:text>.</xsl:text>
    <xsl:value-of select="ancestor::s/@n"/>
    <xsl:value-of select="$sep"/>
    <xsl:value-of select="."/>
    <xsl:value-of select="$sep"/>
    <xsl:value-of select="@hw"/>
    <xsl:value-of select="$sep"/>
    <!-- <xsl:text> </xsl:text> -->
    <xsl:value-of select="@c5"/> <xsl:value-of select="$sep"/>
    <xsl:value-of select="@pos"/>
    <xsl:text>
</xsl:text>
  
  </xsl:template>
  
</xsl:stylesheet>
