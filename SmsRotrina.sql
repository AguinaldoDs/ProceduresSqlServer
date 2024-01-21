USE [YY]
GO
/****** Object:  StoredProcedure [XXXX-XXXX].[RotinaSMSXXXX-XXXX]******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [XXXX-XXXX].[RotinaSMSXXXX-XXXX] AS


-- Projetado por: Aguinaldo Freire da Silva Junior/ Mis - Aguapei
-- Objetivo: Disparo de Sms para devedores 
-- Rotina: Diario ás 09h
-- Ultima Atualização: ----------

----------------> Declara variavei

		declare @RankTelefone int
		set  @RankTelefone = 5
	
		declare @faixaEnvio int
		set @faixaEnvio = (select QuantidadeEnvio from [XXXX-XXXX].[CalendarioSmsRecovey] with(nolock) where convert(date,data) = convert(date,getdate()))

		declare @QtdTel int
		set @QtdTel = 3

----------------> insere base do extrato

		drop table if exists #Ativos

		select
			a.*,
			cast(null as varchar(10)) as faixaEnvio,
			cast(null as varchar(160)) as frase
		into #Ativos
		from [YY].[XXXX-XXXX].extrato a with(nolock)
		where DataInclusaoContrato < getdate()-1
		and SaldoVencido >= 500 and DiasEmAtraso <= 3650
		

----------------> Deleta casos com acordo
-- pagos

		delete from #ativos
		where cnpjcpf in (
		select distinct cnpjcpf 
		from #ativos a
		inner join [dbDataXXXX-XXXXStage].[cob].[Acordos] b on a.iddevedor = b.iddevedor
		inner join [dbDataXXXX-XXXXStage].[cob].[AcordosParcelasPagar] c on b.idacordo = c.idacordo)
		
----------------> Apaga sem cpc
-- retira quase sem cpc até 5 dias e de UltimoSms nao entregue
-- cpc	
		delete from #Ativos
		where convert(date,DataUltimoCpc) > CONVERT(date,getdate()-5)

----------------> deleta casos já enviado no dia

		delete from #Ativos
		where cnpjcpf in (select NR_CNPJ_CPF from glo.SmsAutoHist where convert(date,DataGeracao) = convert(date,getdate()))

-------------> Insere faixas
--> update

		alter table #Ativos
		add Faixa_Envio nvarchar(100)
	
		update a
		set a.Faixa_Envio = case
								when a.SaldoVencido <= 300 then 'Faixa01'
								when a.SaldoVencido between 301 and 2000 then 'Faixa02'
								when a.SaldoVencido between 2001 and 5000 then 'Faixa03'
								when a.SaldoVencido between 5001 and 10000 then 'Faixa04'
								when a.SaldoVencido between 10001 and 50000 then 'Faixa05'
								when a.SaldoVencido > 50001 then 'Faixa06'
								else null end
		from #Ativos a	

--> row number das faixas para psa tel	

		drop table if exists #selectfinal

		select distinct
		a.IdDevedor,
		--c.IdTitulo,
		a.NomeDevedor,
		a.cnpjCpf,
		a.carteira, 
		b.Numero, 
		b.ddd,
		'telefone movel' as TipoTel,
		b.rankTelefone,
		a.faixaAtraso,
		a.FaixaEnvio,
		b.DataRef,
		a.faixa_envio,
		cast(null as varchar(10)) as uf,
		cast(null as varchar(160)) as frase,
		cast(null as varchar(100)) as idfrase,
		row_number() over(partition by a.Faixa_Envio, b.iddevedor order by b.rankTelefone desc) as QuantidadeTel,
		getdate() as DataAtualizada
		into #SelectFinal
		from #Ativos a
		inner join [YY].[XXXX-XXXX].[ResumoPsaTelXXXX-XXXX] b with(nolock) on a.IdDevedor = b.iddevedor
		where b.DataUltimoCpc is not null or Pontuacao >= 10.00
		
		
		delete from #SelectFinal where QuantidadeTel > @QtdTel


		drop table if exists #SelectFinalFaixas
		select a.*,
		cast(null as varchar(5)) as Feriado,
		row_number() over(partition by a.Faixa_Envio order by a.Faixa_Envio, a.iddevedor) as FX
		into #SelectFinalFaixas
		from #SelectFinal a

--- Delete fora da faixa de envio


		--delete a from #SelectFinalFaixas a
		--inner join [XXXX-XXXX].[CalendarioSmsRecovey] b with(nolock) ON convert(date,a.DataAtualizada) = CONVERT(date,b.data)
		--where
		--   a.FX > B.FX1 and a.faixa_envio = 'Faixa01' 
		--or a.FX > B.FX2 and a.faixa_envio = 'Faixa02' 
		--or a.FX > B.FX3 and a.faixa_envio = 'Faixa03' 
		--or a.FX > B.FX4 and a.faixa_envio = 'Faixa04' 
		--or a.FX > B.FX5 and a.faixa_envio = 'Faixa05' 
		--or a.FX > B.FX6 and a.faixa_envio = 'Faixa06' 

-- insere frase e id

		update a
		set a.idFrase = b.Idfrase,
			a.Frase = b.frase
		from #SelectFinalFaixas a
		inner join [XXXX-XXXX].DBXXXX-XXXX.DBO.AUX_FRASES_GERAL_NEW b with(nolock) on b.idFrase = b.idfrase
		where b.data = convert(date,getdate())
		and b.carteira = 'XXXX-XXXX'
		 
-- delete fora do rank/sem frase


		delete from #SelectFinalFaixas where len(ddd) > 2

		delete from #SelectFinalFaixas where len(frase) > 160

		delete from #SelectFinalFaixas where frase is null

		delete from #SelectFinalFaixas where faixa_envio is null

		create index BABYSHARK001 on #SelectFinalFaixas(iddevedor)

		delete a from #SelectFinalFaixas a
		inner join [dbDataXXXX-XXXXStage].[oco].[Ocorrencias] b with(nolock) on a.IdDevedor = b.iddevedor
		where IdTipoOcorrencia in (700,149,223,514) and convert(date,b.DataOcorrencia)<getdate()-120

-- deleta casos com ddd feriado


		update a
			set a.uf =
			 case when a.ddd = 68 then 'AC'
			 when a.ddd = 82 then 'AL'
			 when a.ddd in (92,97)  then 'AM'
			 when a.ddd = 96 then 'AP'
			 when a.ddd in (71,73,74,75,77)  then 'BA'
			 when a.ddd in (85,88)  then 'CE'
			 when a.ddd = 61 then 'DF'
			 when a.ddd in (27,28) then 'ES'
			 when a.ddd in (62,64) then 'GO'
			 when a.ddd in (98,99) then 'MA'
			 when a.ddd in (31,32,33,34,35,37,38) then 'MG'
			 when a.ddd = 67 then 'MS'
			 when a.ddd in (65,66) then 'MT'
			 when a.ddd in (91,93,94) then 'PA'
			 when a.ddd = 83 then 'PB'
			 when a.ddd in (81,87) then 'PE'
			 when a.ddd in (86,89) then 'PI'
			 when a.ddd in (41,42,43,44,45,46) then 'PR'
			 when a.ddd in (21,22,24) then 'RJ'
			 when a.ddd = 84 then 'RN'
			 when a.ddd = 69 then 'RO'
			 when a.ddd = 95 then 'RR'
			 when a.ddd in (51,53,54,55) then 'RS'
			 when a.ddd in (47,48,49) then 'SC'
			 when a.ddd = 79 then 'SE'
			 when a.ddd in (11,15,17,12,19,14,16,13,18) then 'SP'
			 when a.ddd = 63 then 'TO'
			 else null end
			from #SelectFinalFaixas a


-- casos com feriado


		update a
		set a.feriado = case
							when b.idTipoFeriado = 'N' then 'Nacional'
							when b.idTipoFeriado = 'E' then 'Estadual'
						else null end
		from #SelectFinalFaixas a
		inner join [misXXXX-XXXX].[misXXXX-XXXX].[GLO].[Feriados] b on b.data = a.dataRef
		where b.data = getdate()
		AND idtipoFeriado in ('E','N')
		and a.uf = b.uf

		delete a from #SelectFinalFaixas a where a.feriado is not null
		
-------------> select final
		
		drop table if exists #basefinalpsa

		select
		a.*,
		row_number() over(partition by a.DataRef order by a.DataRef) as Ordenacao
		into #baseFinalPsa
		from #SelectFinalFaixas a

		delete a from #baseFinalPsa a
		where a.Ordenacao > @faixaEnvio
		
-------------> gera lote

		Declare @LoteId int

		if object_id('tempdb..##tmpbasesmsYYY','u') is not null drop table ##tmpbasesmsYYY;

		select
			cnpjcpf as NR_CNPJ_CPF,
			nomedevedor as NM_DVD,
			ddd+numero as TELEFONE,
			'1' as CD_EMP,
			'1' as CD_EST,
			'YYY' as CD_CLI,
			frase as FRASE
		into
			##tmpbasesmsYYY
		from
			#baseFinalPsa

		Execute @LoteId = [Sms].[ProcControleLotes]
			   @tempTb='##tmpbasesmsYYY',
			   @CentroCustoId=5,
			   @ModalidadeId=1,
			   @GrpId=YYY,
			   @dirArquivo='\\srv-fl02\Imp_Exp\Export\Sms\XXXX-XXXX\'

-- REALIZA MARCAÇAO DE 50%

	IF OBJECT_ID ('TEMPDB..#LIMITADOR') IS NOT NULL DROP TABLE #LIMITADOR
	SELECT *, ROW_NUMBER() OVER (PARTITION BY Carteira ORDER BY RIGHT(Cnpjcpf,2)) AS ORDEM
	INTO #LIMITADOR
	FROM  #baseFinalPsa

	DECLARE @MEIO AS BIGINT
	SET @MEIO = (SELECT MAX(ORDEM) FROM #LIMITADOR)/2

-------------------------------------------REALIZA O ENVIO PARA O FORNECEDOR 

		IF OBJECT_ID(N'TEMPDB..##SMS_FINAL_XXXX-XXXX_', N'U') IS NOT NULL DROP TABLE ##SMS_FINAL_XXXX-XXXX_

		create table ##SMS_FINAL_XXXX-XXXX_(
			tipo_de_registro nvarchar(160),
			valor_do_registro nvarchar(100),
			mensagem nvarchar(160),
			nome_cliente nvarchar(200),
			contrato nvarchar(50),
			cpfcnpj nvarchar(100),
			codcliente varchar(20),
			tag nvarchar(160),
			coringa1 nvarchar(160),
			coringa2 nvarchar(160),
			coringa3 nvarchar(160),
			coringa4 nvarchar(160),
			coringa5 nvarchar(160),
			id_frase nvarchar(160))

		INSERT INTO ##SMS_FINAL_XXXX-XXXX_ 
		SELECT 'TIPO_DE_REGISTRO','VALOR_DO_REGISTRO','MENSAGEM','NOME_CLIENTE','CONTRATO','CPFCNPJ','CODCLIENTE','TAG','CORINGA1','CORINGA2','CORINGA3','CORINGA4','CORINGA5','ID_FRASE'    ----------- ALTERA€ÇO PARA INCLUSAO DO CABE€ALHO
		UNION ALL
		SELECT 
			'TELEFONE' AS 'TIPO_DE_REGISTRO',
			cast(a.ddd+a.numero as varchar(160)) as 'VALOR_DO_REGISTRO', 
			cast(a.frase as varchar(160)) AS 'MENSAGEM',
			cast(a.NomeDevedor as varchar(160)) AS 'NOME_CLIENTE',
			'000000000' AS 'CONTRATO',
			cast(a.CnpjCpf as varchar) AS 'CPFCNPJ',
			cast(a.Carteira as varchar) AS 'CODCLIENTE',
			'' AS 'TAG',
			'' AS 'CORINGA1',
			'' AS 'CORINGA2',
			'' AS 'CORINGA3',
			'' AS 'CORINGA4',
			'' AS 'CORINGA5',
			cast(a.IdFrase as varchar) AS ID_FRASE

		FROM #baseFinalPsa A
		JOIN #LIMITADOR B ON A.CnpjCpf=B.CnpjCpf
				AND cast(a.ddd+a.numero as varchar(160))=cast(b.ddd+b.numero as varchar(160))
		WHERE
			ORDEM <= @MEIO



	
---------- GERA OS ARQUIVOS NO DIRETORIO C:\ DO SERVIDOR DE MIS

		DECLARE @SQL1A VARCHAR(8000)
		DECLARE @VALTOL1A VARCHAR(8000) 
 
		 BEGIN 
			SET @VALTOL1A = '"\\SRV-\TEMP\ENRIQUECIMENTO XXXX-XXXX\SMS\'+ REPLACE(CONVERT(DATE, getdate()), '-', '') + '_' + REPLACE(CONVERT(VARCHAR, getdate(), 108), ':', '') +'_SMS_XXXX-XXXX_YYY_'+CONVERT(VARCHAR, @LoteId)+'.txt"' 
			SET @SQL1A = 'BCP "SELECT TIPO_DE_REGISTRO,VALOR_DO_REGISTRO,MENSAGEM,NOME_CLIENTE,CPFCNPJ,CODCLIENTE,TAG,CORINGA1,CORINGA2,CORINGA3,CORINGA4,CORINGA5 FROM ##SMS_FINAL_XXXX-XXXX_" QUERYOUT '+@VALTOL1A+' -T -c -t ";"'
			 EXEC XP_CMDSHELL @SQL1A 
		END


-------------------------------------->

		declare @filenames varchar(max)
		select @filenames = replace(@valtol1a,'"','')--+';'+replace(@valtol2a,'"','')
		select @filenames
		declare @volumeDisparado varchar(max)
		set @volumeDisparado = 'Mensagem automatica > favor enviar sms para os casos do arquivo anexo. <br />--------------------<br /> Volume: '+ (select convert(varchar, count(CPFCNPJ)) from ##SMS_FINAL_XXXX-XXXX_) +'<br />--------------------<br /> Atenciosamente, <br /> MIS | Toledo Piza Advogados.'


		exec msdb.dbo.sp_send_dbmail 
		@profile_name			= 'servicoemail',
		@recipients				= '',
		@copy_recipients		= '',
		@body					= @volumeDisparado,
		@body_format			= 'html',
		@subject				= 'ENVIO DE SMS - XXXX-XXXX',
		@file_attachments		= @filenames



--------------------------------------> Carrega Histórico
			insert into YY.SmsAutoHist
			select 
					convert(varchar(20),a.cpfcnpj) as cpfcnpj,
					convert(varchar(300),a.nome_cliente) as nome_cliente,
					convert(char(11),a.valor_do_registro) as valor_do_registro,
					1,
					1,
					YYY,
				   a.mensagem,
			convert(datetime,GETDATE()) as DataGeracao
			from 
			 ##SMS_FINAL_XXXX-XXXX_  a