// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'npm:@supabase/supabase-js@2'

interface KoreaEximRateResponse {
  result: number        // 1: 성공, 2: 데이터 없음, 3: 기타 에러
  cur_unit: string | null      // 통화코드 (예: 'USD', 'JPY(100)')
  cur_nm: string | null        // 통화명 (예: '미국 달러')
  deal_bas_r: string | null    // 매매기준율
  ttb: string | null           // 전신환 받으실 때
  tts: string | null           // 전신환 보내실 때
  bkpr?: string | null         // 매매기준율 (백프라이스)
  yy_efee_r?: string | null    // 연환율
  ten_dd_efee_r?: string | null // 10일 환율
  kftc_bkpr?: string | null     // 한국외환거래소 백프라이스
  kftc_deal_bas_r?: string | null // 한국외환거래소 매매기준율
}

interface EcosStatResponse {
  StatisticSearch?: {
    list_total_count?: number
    row?: EcosStatRow | EcosStatRow[]
    RESULT?: string  // 에러 코드 (예: "정보-200", "에러-100" 등)
    CODE?: string
    MESSAGE?: string
  }
  // 에러 응답일 수도 있음
  RESULT?: string
  CODE?: string
  MESSAGE?: string
}

interface EcosStatRow {
  STAT_CODE: string      // 통계표코드
  STAT_NAME: string      // 통계명
  ITEM_CODE1: string     // 통계항목코드1
  ITEM_NAME1: string     // 통계항목명1
  ITEM_CODE2?: string    // 통계항목코드2
  ITEM_NAME2?: string    // 통계항목명2
  ITEM_CODE3?: string    // 통계항목코드3
  ITEM_NAME3?: string    // 통계항목명3
  ITEM_CODE4?: string    // 통계항목코드4
  ITEM_NAME4?: string    // 통계항목명4
  UNIT_NAME: string      // 단위
  WGT?: string           // 가중치
  TIME: string           // 시점
  DATA_VALUE: string     // 값
}

Deno.serve(async (req) => {
  try {
    // Supabase 클라이언트 초기화
    // SUPABASE_URL과 SUPABASE_SERVICE_ROLE_KEY는 Supabase Edge Functions에서 자동으로 제공됩니다:
    // - 로컬 개발: supabase functions serve 실행 시 자동 설정 (http://127.0.0.1:54321)
    // - 프로덕션: Supabase 플랫폼이 자동으로 제공
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    // 한국수출입은행 API 키 (환경변수에서 가져오기)
    const koreaEximApiKey = Deno.env.get('KOREA_EXIM_API_KEY')
    if (!koreaEximApiKey) {
      return new Response(
        JSON.stringify({ error: 'KOREA_EXIM_API_KEY 환경변수가 설정되지 않았습니다.' }),
        { 
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    // KST 기준 오늘 날짜 계산 (YYYYMMDD 형식)
    const now = new Date()
    // UTC를 KST(UTC+9)로 변환
    const kstTime = new Date(now.getTime() + (9 * 60 * 60 * 1000))
    const searchDate = kstTime.toISOString().slice(0, 10).replace(/-/g, '') // YYYYMMDD

    // 한국수출입은행 AP01(현재환율) API 호출
    const apiUrl = `https://oapi.koreaexim.go.kr/site/program/financial/exchangeJSON?authkey=${koreaEximApiKey}&data=AP01&searchdate=${searchDate}`
    
    console.log(`[환율 API 호출] URL: ${apiUrl}`)
    const response = await fetch(apiUrl)
    
    if (!response.ok) {
      throw new Error(`API 호출 실패: ${response.status} ${response.statusText}`)
    }

    const data: KoreaEximRateResponse[] = await response.json()
    
    // API 응답이 배열이 아니거나 비어있는 경우 처리
    if (!Array.isArray(data) || data.length === 0) {
      return new Response(
        JSON.stringify({ error: 'API 응답이 올바르지 않습니다.', data }),
        { 
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    // result 값에 따른 에러 처리
    // result: 1 = 성공, 2 = 데이터 없음, 3 = 기타 에러
    const firstItem = data[0]
    if (firstItem.result !== 1) {
      const errorMessages: Record<number, string> = {
        2: 'API 응답 오류: 해당 날짜의 데이터가 없습니다.',
        3: 'API 응답 오류: 인증키 오류 또는 서버 오류가 발생했습니다.',
      }
      const errorMsg = errorMessages[firstItem.result] || `API 응답 오류: result=${firstItem.result}`
      return new Response(
        JSON.stringify({ error: errorMsg, result: firstItem.result, data }),
        { 
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    // 유효한 데이터만 필터링 (result가 1이고 cur_unit이 있는 경우)
    // 한국에서 주로 사용하는 통화: USD, JPY, CNY만 선택
    // 중국 위안의 경우 cur_unit이 'CNY'가 아닐 수도 있어 통화명까지 함께 체크
    const TARGET_CURRENCIES = new Set(['USD', 'JPY(100)', 'CNY', 'CNH'])

    const isTargetCurrency = (item: KoreaEximRateResponse): boolean => {
      const unit = item.cur_unit
      const name = item.cur_nm || ''
      if (!unit) return false
      if (TARGET_CURRENCIES.has(unit)) return true
      // 중국 위안 보정: 통화명이 '중국', '위안'을 포함하면 포함
      if (name.includes('중국') || name.includes('위안')) return true
      return false
    }

    const validData = data.filter((item) => item.result === 1 && isTargetCurrency(item))

    if (validData.length === 0) {
      return new Response(
        JSON.stringify({ error: '유효한 환율 데이터가 없습니다.', data }),
        { 
          status: 400,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    // searchdate를 Date 형식으로 변환 (YYYYMMDD -> YYYY-MM-DD)
    const baseDate = `${searchDate.slice(0, 4)}-${searchDate.slice(4, 6)}-${searchDate.slice(6, 8)}`

    // 데이터 파싱 및 변환
    const insertData = validData.map((item) => {
      // 숫자 문자열에서 쉼표 제거 후 숫자로 변환
      const parseNumeric = (value: string | null): number => {
        if (!value || value === '-' || value === '') return 0
        return parseFloat(value.replace(/,/g, ''))
      }

      return {
        base_date: baseDate,
        base_time: null, // 필요시 추가
        currency_code: item.cur_unit!,
        currency_name: item.cur_nm || null,
        deal_bas_r: parseNumeric(item.deal_bas_r),
        ttb: parseNumeric(item.ttb),
        tts: parseNumeric(item.tts),
        provider: 'KOREA_EXIM',
        raw: item as unknown as Record<string, unknown>, // 원본 JSON 저장
      }
    })

    console.log(`[데이터 변환 완료] ${insertData.length}개 환율 데이터`)

    // fx_rates 테이블에 insert (upsert 사용하여 중복 방지)
    const { data: insertedData, error } = await supabase
      .from('fx_rates')
      .upsert(insertData, {
        onConflict: 'base_date,currency_code,provider',
        ignoreDuplicates: false, // 중복 시 업데이트
      })
      .select()

    if (error) {
      console.error('[DB 삽입 오류 - fx_rates]', error)
      return new Response(
        JSON.stringify({ 
          error: '데이터베이스 삽입 실패 (fx_rates)',
          details: error.message 
        }),
        { 
          status: 500,
          headers: { 'Content-Type': 'application/json' }
        }
      )
    }

    console.log(`[삽입 완료] fx_rates: ${insertedData?.length || 0}개 레코드`)

    // =========================
    // 2) 한국은행 ECOS API (기준금리) 호출 및 ecos_stat_meta 삽입
    // =========================

    // 한국은행 ECOS API 인증키 (환경변수에서 가져오기)
    const ecosApiKey = Deno.env.get('ECOS_API_KEY')
    let ecosInsertedCount = 0 // ECOS 데이터 삽입 개수 추적
    let ecosErrorMessage: string | null = null // ECOS API 에러 메시지
    
    console.log(`[ECOS API 키 확인] ECOS_API_KEY=${ecosApiKey ? '설정됨' : '없음'}`)
    
    if (!ecosApiKey) {
      const availableEnvVars = Object.keys(Deno.env.toObject()).filter(k => k.includes('ECOS') || k.includes('API'))
      ecosErrorMessage = 'ECOS_API_KEY 환경변수가 설정되지 않았습니다. .env 파일 또는 config.toml의 edge_runtime.secrets 섹션을 확인하세요.'
      console.log('[경고] ECOS_API_KEY 환경변수가 설정되지 않았습니다. ECOS API 호출을 건너뜁니다.')
      console.log('[디버깅] 사용 가능한 환경변수:', availableEnvVars)
      // ECOS API 키가 없어도 환율 데이터는 이미 저장되었으므로 계속 진행
    } else {
      console.log(`[ECOS API 시작] 인증키 확인 완료, API 호출 시작`)
      
      // 통계표코드: 722Y001 (한국은행 기준금리)
      const statCode = '722Y001'
      // 항목코드: 0101000 (한국은행 기준금리)
      const itemCode = '0101000'
      // 주기: 일간(D) - 기준금리는 일간 데이터
      const cycle: string = 'D'
      
      // 검색 기간: 최근 7일 데이터를 가져와서 가장 최신 데이터만 저장 (YYYYMMDD 형식)
      const endDate = searchDate // 오늘 날짜
      const startDate = (() => {
        const date = new Date(kstTime)
        date.setDate(date.getDate() - 7) // 7일 전
        return date.toISOString().slice(0, 10).replace(/-/g, '')
      })()

      // ECOS API URL 구성
      // 형식: /api/StatisticSearch/{인증키}/{요청유형}/{언어구분}/{요청시작건수}/{요청종료건수}/{통계표코드}/{주기}/{검색시작일자}/{검색종료일자}/{통계항목코드1}/?/?/?
      const ecosUrl = `https://ecos.bok.or.kr/api/StatisticSearch/${ecosApiKey}/json/kr/1/10/${statCode}/${cycle}/${startDate}/${endDate}/${itemCode}/?/?/?`

      console.log(`[ECOS API 호출 시작]`)
      console.log(`[ECOS API URL] ${ecosUrl}`)
      console.log(`[ECOS API 파라미터] statCode=${statCode}, itemCode=${itemCode}, cycle=${cycle}, startDate=${startDate}, endDate=${endDate}`)
    
      try {
        console.log(`[ECOS API] fetch 호출 중...`)
        const ecosResponse = await fetch(ecosUrl)
        
        console.log(`[ECOS API 응답 상태] ${ecosResponse.status} ${ecosResponse.statusText}`)
        
        if (!ecosResponse.ok) {
          const errorText = await ecosResponse.text()
          console.error(`[ECOS API 호출 실패] 상태: ${ecosResponse.status}, 응답: ${errorText.substring(0, 500)}`)
          throw new Error(`ECOS API 호출 실패: ${ecosResponse.status} ${ecosResponse.statusText}`)
        }

        const ecosResponseText = await ecosResponse.text()
        console.log(`[ECOS API 응답 원본 전체]`, ecosResponseText)
        
        const ecosData: EcosStatResponse = await JSON.parse(ecosResponseText)
        console.log(`[ECOS API 응답 파싱 완료]`, JSON.stringify(ecosData, null, 2))
        
        // 응답 구조 확인
        if (!ecosData.StatisticSearch) {
          console.error('[ECOS API] StatisticSearch가 응답에 없습니다.')
          console.error('[ECOS API] 전체 응답 키:', Object.keys(ecosData))
          console.error('[ECOS API] 전체 응답:', JSON.stringify(ecosData, null, 2))
          // StatisticSearch가 없어도 데이터가 없는 것으로 처리하고 계속 진행
          console.log('[ECOS API] 데이터가 없습니다. 계속 진행합니다.')
        } else {
          const searchData = ecosData.StatisticSearch
          
          // 에러 코드 확인 (StatisticSearch 내부)
          // "정보-200"은 "해당하는 데이터가 없습니다"를 의미하므로 에러로 처리하지 않음
          if (searchData.RESULT && searchData.RESULT !== '정보-200') {
            const errorMsg = searchData.MESSAGE || searchData.RESULT || searchData.CODE
            console.error('[ECOS API 에러]', errorMsg)
            throw new Error(`ECOS API 에러: ${errorMsg}`)
          }
          
          // "정보-200" 또는 데이터가 없는 경우
          if (searchData.RESULT === '정보-200' || !searchData.row || searchData.list_total_count === 0) {
            console.log('[ECOS API] 최근 7일 내 데이터가 없습니다. list_total_count:', searchData.list_total_count)
            console.log('[ECOS API] RESULT:', searchData.RESULT)
            console.log('[ECOS API] MESSAGE:', searchData.MESSAGE)
            // 데이터가 없어도 정상적으로 처리 (에러가 아님)
          } else {
          // row가 배열인지 단일 객체인지 확인
          const rows = Array.isArray(searchData.row)
            ? searchData.row
            : [searchData.row]

          console.log(`[ECOS API] row 개수: ${rows.length}`)

          if (rows.length > 0) {
          // TIME 값으로 정렬하여 가장 최신 데이터만 선택
            const sortedRows = rows.sort((a, b) => b.TIME.localeCompare(a.TIME))
            const latestRow = sortedRows[0] // 가장 최신 데이터
            
            console.log(`[ECOS API] 가장 최신 데이터 선택: TIME=${latestRow.TIME}, DATA_VALUE=${latestRow.DATA_VALUE}`)
            
            // 가장 최신 데이터만 ecos_base_rate 테이블에 저장
            // DATA_VALUE를 숫자로 변환 (빈 문자열이나 null인 경우 null 처리)
            let dataValue: number | null = null
            if (latestRow.DATA_VALUE && latestRow.DATA_VALUE.trim() !== '') {
              const parsed = parseFloat(latestRow.DATA_VALUE)
              dataValue = isNaN(parsed) ? null : parsed
            }

            const ecosInsertData = [{
              stat_code: latestRow.STAT_CODE,
              stat_name: latestRow.STAT_NAME || null,
              cycle: cycle,
              unit_name: latestRow.UNIT_NAME || null,
              time_period: latestRow.TIME, // TIME 값을 그대로 time_period로 사용
              data_value: dataValue,
              raw: latestRow as unknown as Record<string, unknown>,
            }]

            console.log(`[ECOS 데이터 변환 완료] ${ecosInsertData.length}개 기준금리 데이터`)
            console.log(`[ECOS 삽입 데이터 샘플]`, JSON.stringify(ecosInsertData[0]))
            console.log(`[ECOS 삽입 데이터 개수] ${ecosInsertData.length}개`)

            // ecos_base_rate 테이블에 insert
            // 참고: 테이블에 unique constraint가 (stat_code, time_period)로 설정되어 있으므로
            // upsert의 onConflict가 작동합니다. 먼저 insert를 시도하고
            // 중복 에러가 발생하면 upsert로 재시도
            const { data: insertedEcosData, error: ecosError } = await supabase
              .from('ecos_base_rate')
              .insert(ecosInsertData)
              .select()

            if (ecosError) {
              console.error('[DB 삽입 오류 - ecos_base_rate]', ecosError)
              console.error('[에러 상세]', JSON.stringify(ecosError))
              
              // 중복 키 에러인 경우 upsert로 재시도
              if (ecosError.code === '23505' || ecosError.message?.includes('duplicate')) {
                console.log('[재시도] 중복 키 에러 발생. upsert로 재시도합니다.')
                const { data: insertedEcosData2, error: ecosError2 } = await supabase
                  .from('ecos_base_rate')
                  .upsert(ecosInsertData, {
                    onConflict: 'stat_code,time_period',
                    ignoreDuplicates: false,
                  })
                  .select()
                
                if (ecosError2) {
                  console.error('[DB upsert 오류 - ecos_base_rate]', ecosError2)
                } else {
                  ecosInsertedCount = insertedEcosData2?.length || 0
                  console.log(`[삽입 완료] ecos_base_rate: ${ecosInsertedCount}개 레코드 (upsert 사용)`)
                }
              }
            } else {
              ecosInsertedCount = insertedEcosData?.length || 0
              console.log(`[삽입 완료] ecos_base_rate: ${ecosInsertedCount}개 레코드`)
            }
          } else {
            console.log('[ECOS API] rows.length가 0입니다.')
          }
          } // else 블록 종료 (데이터가 있는 경우)
        } // else 블록 종료 (StatisticSearch가 있는 경우)
      } catch (ecosError) {
        ecosErrorMessage = ecosError instanceof Error ? ecosError.message : String(ecosError)
        console.error('[ECOS API 오류]', ecosError)
        console.error('[ECOS API 오류 상세]', ecosErrorMessage)
        // ECOS API 오류가 발생해도 환율 데이터는 이미 저장되었으므로 계속 진행
      }
    } // else 블록 종료 (ecosApiKey가 있을 때만 실행)

    const responseData = {
      success: true,
      message: '환율 데이터가 성공적으로 저장되었습니다.',
      inserted_count: insertedData?.length || 0,
      search_date: searchDate,
      ecos_api_called: !!ecosApiKey,
      ecos_inserted_count: ecosInsertedCount,
      ecos_error: ecosErrorMessage || null,
    }
    
    console.log(`[최종 응답]`, JSON.stringify(responseData))
    
    return new Response(
      JSON.stringify(responseData),
      {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }
    )

  } catch (error) {
    console.error('[에러 발생]', error)
    return new Response(
      JSON.stringify({
        error: '서버 오류가 발생했습니다.',
        details: error instanceof Error ? error.message : String(error),
      }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }
    )
  }
})

/* 
환경변수 설정 필요:
- SUPABASE_URL: Supabase 프로젝트 URL
- SUPABASE_SERVICE_ROLE_KEY: Supabase Service Role Key (테이블에 직접 쓰기 권한 필요)
- KOREA_EXIM_API_KEY: 한국수출입은행 환율 API 키 (AP01)
- ECOS_API_KEY: 한국은행 ECOS API 인증키 (기본값: XK6MZX0Y6PU2BKSH3KSI)

로컬 테스트:
supabase functions serve fx_fetcher

배포:
supabase functions deploy fx_fetcher

호출 예시:
curl -i --location --request POST 'https://YOUR_PROJECT.supabase.co/functions/v1/fx_fetcher' \
  --header 'Authorization: Bearer YOUR_ANON_KEY' \
  --header 'Content-Type: application/json'
*/
