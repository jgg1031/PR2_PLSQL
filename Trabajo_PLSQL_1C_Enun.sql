DROP TABLE detalle_pedido CASCADE CONSTRAINTS;
DROP TABLE pedidos CASCADE CONSTRAINTS;
DROP TABLE platos CASCADE CONSTRAINTS;
DROP TABLE personal_servicio CASCADE CONSTRAINTS;
DROP TABLE clientes CASCADE CONSTRAINTS;

DROP SEQUENCE seq_pedidos;


-- Creación de tablas y secuencias



CREATE SEQUENCE seq_pedidos
    START WITH 1       -- Empieza desde 1
    INCREMENT BY 1     -- Aumenta de 1 en 1
    NOMAXVALUE         -- Sin límite máximo
    NOCYCLE            -- No se reinicia
    CACHE 20;          -- Guarda 20 valores en caché para optimizar rendimiento

CREATE TABLE clientes (
    id_cliente INTEGER PRIMARY KEY,
    nombre VARCHAR2(100) NOT NULL,
    apellido VARCHAR2(100) NOT NULL,
    telefono VARCHAR2(20)
);

CREATE TABLE personal_servicio (
    id_personal INTEGER PRIMARY KEY,
    nombre VARCHAR2(100) NOT NULL,
    apellido VARCHAR2(100) NOT NULL,
    pedidos_activos INTEGER DEFAULT 0 CHECK (pedidos_activos <= 5)
);

CREATE TABLE platos (
    id_plato INTEGER PRIMARY KEY,
    nombre VARCHAR2(100) NOT NULL,
    precio DECIMAL(10, 2) NOT NULL,
    disponible INTEGER DEFAULT 1 CHECK (DISPONIBLE in (0,1))
);

CREATE TABLE pedidos (
    id_pedido INTEGER PRIMARY KEY,
    id_cliente INTEGER REFERENCES clientes(id_cliente),
    id_personal INTEGER REFERENCES personal_servicio(id_personal),
    fecha_pedido DATE DEFAULT SYSDATE,
    total DECIMAL(10, 2) DEFAULT 0
);

CREATE TABLE detalle_pedido (
    id_pedido INTEGER REFERENCES pedidos(id_pedido),
    id_plato INTEGER REFERENCES platos(id_plato),
    cantidad INTEGER NOT NULL,
    PRIMARY KEY (id_pedido, id_plato)
);


	
-- Procedimiento a implementar para realizar la reserva
create or replace procedure registrar_pedido(
    arg_id_cliente      INTEGER, 
    arg_id_personal     INTEGER, 
    arg_id_primer_plato INTEGER DEFAULT NULL,
    arg_id_segundo_plato INTEGER DEFAULT NULL
) is 
    --Declaración de excepciones
    plato_no_disponible exception;
    pragma exception_init(plato_no_disponible, -20001);
    msg_plato_no_disponible constant varchar(50) := 'Uno de los plato seleccionado no está disponible';
    
    pedido_sin_platos exception;
    pragma exception_init(pedido_sin_platos, -20002);
    msg_pedido_sin_platos constant varchar(50) := 'El pedido debe contener al menos un plato';
    
    personal_ocupado exception;
    pragma exception_init(personal_ocupado, -20003);
    msg_personal_ocupado constant varchar(50) := 'El personal de servicio tiene demasiados pedidos';
    
    plato_inexistente exception;
    pragma exception_init(plato_inexistente, -20004);
    msg_plato_inexistente_plato1 constant varchar(50) := 'El primer plato seleccionado no existe';
    msg_plato_inexistente_plato2 constant varchar(50) := 'El segundo plato seleccionado no existe';
    
    --Declaración de cursores
    CURSOR vPlato1Disponible IS 
        SELECT id_plato, disponible FROM platos WHERE id_plato = arg_id_primer_plato;

    varIdPlato1 platos.id_plato%type;
    varPlatoDisponible1 platos.disponible%type;
    
    CURSOR vPlato2Disponible IS
        SELECT id_plato, disponible FROM platos WHERE id_plato = arg_id_segundo_plato;

    varIdPlato2 platos.id_plato%type;
    varPlatoDisponible2 platos.disponible%type;
        
    --Personal disponible
    varPersonalDisponible personal_servicio.pedidos_activos%type;
    
    varTotalPedido pedidos.total%type;
    var_id_pedido pedidos.id_pedido%type;
    
 begin
    
    OPEN vPlato1Disponible;
    FETCH vPlato1Disponible INTO varIdPlato1, varPlatoDisponible1;
    
    OPEN vPlato2Disponible;
    FETCH vPlato2Disponible INTO varIdPlato2, varPlatoDisponible2;
    
    --Comprobar que los platos están disponibles
    IF NVL(varPlatoDisponible1, 1) = 0 OR NVL(varPlatoDisponible2, 1) = 0
    THEN
        CLOSE vPlato1Disponible;
        CLOSE vPlato2Disponible;
        ROLLBACK;
        raise_application_error(-20001, msg_plato_no_disponible);
    END IF;
    
    --Comprobar que se pasan al menos un plato
    IF arg_id_primer_plato IS NULL AND arg_id_segundo_plato IS NULL
    THEN
        ROLLBACK;
        raise_application_error(-20002, msg_pedido_sin_platos);
    END IF;
    
    --Comprobar que el personal tiene suficientes pedidos
    SELECT pedidos_activos INTO varPersonalDisponible FROM personal_servicio 
        WHERE id_personal = arg_id_personal;
    IF varPersonalDisponible > 5
    THEN 
        ROLLBACK;
        raise_application_error(-20003, msg_personal_ocupado);
    END IF;
 
    --Comprobar que el primer plato existe
    IF varIdPlato1 IS NULL
    THEN
        CLOSE vPlato1Disponible;
        ROLLBACK;
        raise_application_error(-20004, msg_plato_inexistente_plato1);
    END IF;
    
    --Comprobar que el segundo plato existe
    IF varIdPlato2 IS NULL
    THEN
        CLOSE vPlato2Disponible;
        ROLLBACK;
        raise_application_error(-20004, msg_plato_inexistente_plato2);
    END IF;
    
    var_id_pedido := seq_pedidos.NEXTVAL;
  --Obtener la suma del total del pedido
  SELECT SUM(precio) INTO varTotalPedido FROM platos WHERE id_plato IN (arg_id_primer_plato, arg_id_segundo_plato);
  --Añadir pedido a la tabla de pedidos
  INSERT INTO pedidos (id_pedido, id_cliente, id_personal, fecha_pedido, total) VALUES(var_id_pedido ,arg_id_cliente, arg_id_personal, SYSDATE, varTotalPedido);
  --Añadir los detalles del pedido
  INSERT INTO detalles_pedido VALUES(var_id_pedido, arg_id_primer_plato);
  INSERT INTO detalles_pedido VALUES(var_id_pedido, arg_id_segundo_plato);
  
  --Añadir un pedido mas al personal
  UPDATE personal_servicio SET pedidos_activos = ((SELECT pedidos_activos FROM personal_servicio WHERE id_personal = arg_id_personal) + 1) WHERE id_personal = arg_id_personal;
  
  
end;
/

------ Deja aquí tus respuestas a las preguntas del enunciado:
-- NO SE CORREGIRÁN RESPUESTAS QUE NO ESTÉN AQUÍ (utiliza el espacio que necesites apra cada una)
-- * P4.1
--  Para garantizar que un miembro del personal no supera el límite de pedidos activos lo definimos en el procedimiento 'registrar_pedido'. Antes de registrar el pedido se verifica cuantos pedidos activos tiene el miembro del personal, si es mayor a 5 se lanza una excepción que impide la asignacion del pedido. 
-- * P4.2
--  Para evitar este suceso, utilizaremos una cláusula (SELECT ... FOR UPDATE). De esta manera se bloquea la fila del personal de servicio evitando que otro proceso modifique 'pedidos_activos' simultanea.
-- * P4.3
--
-- * P4.4
--
-- * P4.5
-- 



create or replace
procedure reset_seq( p_seq_name varchar )
is
    l_val number;
begin
    execute immediate
    'select ' || p_seq_name || '.nextval from dual' INTO l_val;

    execute immediate
    'alter sequence ' || p_seq_name || ' increment by -' || l_val || 
                                                          ' minvalue 0';
    execute immediate
    'select ' || p_seq_name || '.nextval from dual' INTO l_val;

    execute immediate
    'alter sequence ' || p_seq_name || ' increment by 1 minvalue 0';

end;
/


create or replace procedure inicializa_test is
begin
    
    reset_seq('seq_pedidos');
        
  
    delete from Detalle_pedido;
    delete from Pedidos;
    delete from Platos;
    delete from Personal_servicio;
    delete from Clientes;
    
    -- Insertar datos de prueba
    insert into Clientes (id_cliente, nombre, apellido, telefono) values (1, 'Pepe', 'Perez', '123456789');
    insert into Clientes (id_cliente, nombre, apellido, telefono) values (2, 'Ana', 'Garcia', '987654321');
    
    insert into Personal_servicio (id_personal, nombre, apellido, pedidos_activos) values (1, 'Carlos', 'Lopez', 0);
    insert into Personal_servicio (id_personal, nombre, apellido, pedidos_activos) values (2, 'Maria', 'Fernandez', 5);
    
    insert into Platos (id_plato, nombre, precio, disponible) values (1, 'Sopa', 10.0, 1);
    insert into Platos (id_plato, nombre, precio, disponible) values (2, 'Pasta', 12.0, 1);
    insert into Platos (id_plato, nombre, precio, disponible) values (3, 'Carne', 15.0, 0);

    commit;
end;
/

exec inicializa_test;

-- Completa lost test, incluyendo al menos los del enunciado y añadiendo los que consideres necesarios

create or replace procedure test_registrar_pedido is
begin
	 
  --caso 1 Pedido correct, se realiza
  begin
    inicializa_test;
  end;
  
  -- Idem para el resto de casos

  /* - Si se realiza un pedido vac´ıo (sin platos) devuelve el error -200002.
     - Si se realiza un pedido con un plato que no existe devuelve en error -20004.
     - Si se realiza un pedido que incluye un plato que no est´a ya disponible devuelve el error -20001.
     - Personal de servicio ya tiene 5 pedidos activos y se le asigna otro pedido devuelve el error -20003
     - ... los que os puedan ocurrir que puedan ser necesarios para comprobar el correcto funcionamiento del procedimiento
*/
  
end;
/


set serveroutput on;
exec test_registrar_pedido;
